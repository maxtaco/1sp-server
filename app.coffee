express = require "express"
argv = require('optimist').argv
dynamo = require 'dynamo'

# =======================================================================
# 

# =======================================================================

class Server
  
  #-----------------------------------------
  
  constructor : () ->
    @_cache = {}
    @_client = dynamo.createClient()
    @_db = @_client.get("us-east-1")
    @_tab = "1sp_public_data"

  #-----------------------------------------

  db : () -> @_db.get(@_tab)

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
    rc = 1
    
    if not key? or not val?
      err = "need 'id' and 'val' keys"
    else if key.length < 12
      err = "needed a key of sufficient length"
    else
      @_cache[key] = data
      await
        @_db.get(@_tab).put({key : id, data : data}).save defer err, data
      if err
        @log "error in putting data to dynamo: #{err}"
      else
        rc = 0

    jres = { rc, err }
    @output res, jres
  
  #-----------------------------------------
  
  handleGet : (req, res) ->
    id = req.params.id
    outdat = null
    cv = @_cache[id]
    err = null
    
    if not cv
      console.log "Fetching item for #{id}"
      item = @db().get(id)
      console.log "Item: #{JSON.stringify item}"
      await item.fetch defer err, dydat
      if err
        @log "error in fetching from dynamo: #{err}"
      else if not (data = dydat.data)?
        @log "Data element does not have data: #{JSON.stringify dydat}"
      else
        outdat = data
        @_cache[id] = cv
    else
      outdat = cv

    jres = {}
    if outdat
      jres.rc = 0
      jres.data = outdat
    else
      jres.rc = 1
      jres.err = err if err

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
