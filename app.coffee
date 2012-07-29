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
    data = req.body.data
    err = null
    rc = STATUS.OK
    
    if not key? or not val?
      err = "need 'id' and 'val' keys"
      rc = STATUS.BAD_INPUT
    else if key.length < 12
      err = "needed a key of sufficient length"
      rc = STATUS.BAD_INPUT
    else
      @_cache[key] = data
      await
        @_db.get(@_tab).put({key : id, data : data}).save defer err, data
      if err
        rc = STATUS.AWS_ERROR
        @log "error in putting data to dynamo: #{err}"
      else
        rc = STATUS.OK

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

app.get "/:id",  (req,res) -> server.handleGet  req, res
app.post "/:id", (req,res) -> server.handlePost req, res

port = argv.port or argv.p or 3000

app.listen port
