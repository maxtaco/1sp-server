express = require "express"
argv = require('optimist').argv
dynamo = require 'dynamo'

# =======================================================================

STATUS =
  OK : 0
  NOT_FOUND : 1
  AWS_ERROR : 2
  BAD_DATA : 3
  BAD_INPUT : 4
  BAD_JSON : 5

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
    key = req.params.id
    err = null
    rc = STATUS.OK
    data = null

    rawdata = req.body.data
    if not key? or not rawdata?
      err = "need 'id' and 'data' keys"
      rc = STATUS.BAD_INPUT
    else if key.length < 12
      err = "needed a key of sufficient length"
      rc = STATUS.BAD_INPUT
    else
      try 
        data = JSON.parse rawdata
      catch e
        rc = STATUS.BAD_JSON
        err = "Bad json string as input: #{rawdata}"
        
    if rc is STATUS.OK
      @_cache[key] = data
      args = { key, rawdata }
      await @table().put(args).save defer dyerr, dydata
      if dyerr
        err = "Error in PUT do dynamo: #{dyerr}"
        rc = STATUS.AWS_ERROR
      else
        rc = STATUS.OK

    if err?
      @log "Error in handlePut: #{err}"

    jres = { rc, err }
    @output res, jres
  
  #-----------------------------------------
  
  handleGet : (req, res) ->
    id = req.params.id
    outdat = null
    cv = @_cache[id]
    e_str = null
    rc = STATUS.OK

    err = (x) =>
      @log x
      e_str = x
    
    if not cv
      await @table().get({key : id}).fetch defer dyerr, dydat
      if dyerr
        err "error in fetching from dynamo: #{dyerr}"
        rc = STATUS.AWS_ERROR
      else if not dydat?
        err "no entry found for key '#{id}'"
        rc = STATUS.NOT_FOUND
      else if not (data = dydat.data)?
        err "Data element does not have data: #{JSON.stringify dydat}"
        rc = STATUS.BAD_DATA
      else
        outdat = data
        @_cache[id] = cv
    else
      outdat = cv

    jres = { rc }
    if outdat
      jres.data = outdat
    else
      jres.err = e_str if e_str

    @output res, jres

  #-----------------------------------------
  
# =======================================================================

server = new Server()

# =======================================================================

app = express.createServer()
app.use express.bodyParser()

app.get "/:id",  (req,res) -> server.handleGet  req, res
app.post "/:id", (req,res) -> server.handlePost req, res

port = argv.port or argv.p or 3000

app.listen port
