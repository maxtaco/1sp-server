express = require "express"
argv = require('optimist').argv
dynamo = require 'dynamo'
validator = require 'validator'
lock = require 'lib/lock'

# =======================================================================

STATUS =
  OK : 0
  NOT_FOUND : 1
  AWS_ERROR : 2
  BAD_DATA : 3
  BAD_INPUT : 4
  BAD_JSON : 5
  BAD_PW : 6

# =======================================================================

is_email_valid = (em) -> validator.check(em).len(4,128).isEmail()
is_pw_valid = (pw) -> validator.check(pw).is(/^[a-zA-Z0-9]+$/).len(8,20)
unix_time = () -> Math.floor ((new Date ()).getTime() / 1000);

# =======================================================================

class CacheObj

  # If more than 3 bad attempts in the last 60 seconds, wait for 20s
  WINDOW : 60
  N_BAD : 3
  WAIT : 20

  constructor : (@_key) ->
    @_lock = new Lock { locked : true }
    @_payload = null
    @_pw = null
    @_attempts = []
    @_attempt_map = {}

  set_pw : (p) -> @_pw = p
  set_payload : (p) -> @_payload = p
  
  set_blob : (b) ->
    if b.pw? and b.payload?
      @set_pw b.pw
      @set_payload b.payload
      true
    else
      false

  _prune_attempts : () ->
    now = unix_time()
    i = 0
    while @_attempts.length and (now - @_attempts[i].time > @WINDOW)
      delete @_attempt_map[@_attempts[i].pw]
      i++
    @_bad_attempts = @_bad_attempts[i..]

  lock_and_delay : (cb) ->
    await @_lock.acquire defer()
    await @_delay defer()
    cb()

  _delay : (cb) ->
    @_prune_attempts()
    if @_attempts.length >= @N_BAD
      await setTimeout defer(), WAIT*1000
    cb()

  payload : () -> @_payload
  check_pw : (pw) -> @_pw is pw

  add_password_attempt : (pw) ->
    if not _attempt_map[pw]?
      @_attempts.push { time: unix_time(), pw }

  export : () -> JSON.stringify { pw : @_pw, payload:  @_payload }

  release : () ->
    @_lock.release()

# =======================================================================

class Server
  
  #-----------------------------------------
  
  constructor : () ->
    @_cache = {}
    @_client = dynamo.createClient()
    @_db = @_client.get("us-east-1")
    @_tab = "1sp_public_data"

  #-----------------------------------------

  table : () -> @_db.get(@_tab)

  #-----------------------------------------
  
  log : (x) -> console.log x

  #-----------------------------------------
  
  setJson : (res) ->
    res.contentType "application/json"

  #-----------------------------------------

  output : (res, jres) ->
    @setJson res
    res.send JSON.stringify jres
    
  #-----------------------------------------
  
  handlePost : (req, res) ->
    key = req.params.em
    pw = req.params.pw
    err = null
    rc = STATUS.OK
    data = null

    rawdata = req.body.data
    if not key? or not rawdata?
      err = "need 'id' and 'data' keys"
      rc = STATUS.BAD_INPUT
    else if not is_email_valid key
      err = "need a valid email, not #{key}"
      rc = STATUS.BAD_INPUT
    else if not is_pw_valid pw
      err = "need a valid PW, not #{pw}"
      rc = STATUS.BAD_INPUT
    else
      try 
        data = JSON.parse rawdata
      catch e
        rc = STATUS.BAD_JSON
        err = "Bad json string as input: #{rawdata}"

    if rc is STATUS.OK
      # Fetch the object from cache, to make sure we haven't
      # had a PW violation. This will give us a valid cache
      # object back, which we can then populate.  The dummy
      # is that we don't need what was previously in the cache
      await @_fetch key, pw, { do_put : true }, defer rc, e_str, dummy, cobj
        
    if rc is STATUS.OK
      cobj.set_payload data
      args = { key, data : cobj.export() }
      await @table().put(args).save defer dyerr, dydata
      if dyerr
        err = "Error in PUT do dynamo: #{dyerr}"
        rc = STATUS.AWS_ERROR
      else
        rc = STATUS.OK

    if err?
      @log "Error in handlePut: #{err}"

    # obfuscate PW failures!
    if rc is STATUS.BAD_PW
      rc = STATUS.OK
      err = null

    jres = { rc, err }
    
    cobj.release() if cobj?
    
    @output res, jres

  #-----------------------------------------

  _not_found_emsg : (key) -> "no data found for key '#{key}'"
   
  #-----------------------------------------

  _fetch : (key, pw, opts, cb) ->

    rc = STATUS.OK
    err = null
    
    cobj = @_cache[key]
    if not cobj?
      cobj = new CacheObj key
      @_cache[key] = cobj
      await @table().get({key : id}).fetch defer dyerr, dydat
      if dyerr
        err = "error in fetching from dynamo: #{dyerr}"
        rc = STATUS.AWS_ERROR
      else if not dydat?
        if opts.do_put
          cobj.set_pw pw
        else
          err = @_not_found_emsg key
          rc = STATUS.NOT_FOUND
      else if not (blob = dydat.data)?
        err  = "Data element does not have data: #{JSON.stringify dydat}"
        rc = STATUS.BAD_DATA
      else if not cobj.set_blob blob
        err = "Blob found did not have required fields"
        rc = STATUS.BAD_DATA
    else
      await cobj.lock_and_delay defer()

    if cobj? and not cobj.check_pw pw
      err = "Bad password given"
      rc = STATUS.BAD_PW
      
    cobj.add_password_attempt pw if cobj?

    payload = cobj.payload() if rc is STATUS.OK
    
    # release any locks we might have, so that others can
    # grab it.  They might have to wait for it too if there
    # have been too many PW failures
    cobj.release() if cobj? and not opts.do_put
      
    cb rc, err, payload, cobj
  
  #-----------------------------------------
  
  handleGet : (req, res) ->
    id = req.params.em
    pw = req.params.pw
    
    await @_fetch id, pw, {}, defer e_str, rc, payload
    @log "_fetch: #{e_str}" if e_str?
    jres = { rc }

    # Now, obfuscate password errors
    if rc is STATUS.BAD_PW
      rc = STATUS.NOT_FOUND
      e_str = @_not_found_emsg id
      
    if rc is STATUS.OK
      jres.data = payload
    else
      jres.err = e_str if e_str

    @output res, jres

  #-----------------------------------------
  
# =======================================================================

server = new Server()

# =======================================================================

app = express.createServer()
app.use express.bodyParser()

app.get "/:em/:pw",  (req,res) -> server.handleGet  req, res
app.post "/:em/:pw", (req,res) -> server.handlePost req, res

port = argv.port or argv.p or 3000

app.listen port
