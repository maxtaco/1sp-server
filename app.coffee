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
    @_tb = "1sp_public_data"

  #-----------------------------------------
  
  log : (x) -> console.log x

  #-----------------------------------------
  
  setJson : (res) ->
    res.contentType "application/json"

  #-----------------------------------------
  
  handleGet : (req, res) ->
    id = req.params.id
    outdat = null
    @setJson res
    cv = @_cache[id]
    err = null
    
    if not cv
      await
        @_db.get(@_tb).query({key : id }).get("data").fetch defer err, data
      if err
        @log "error in fetching from dynamo: #{err}"
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

    res.send JSON.stringify jres

  #-----------------------------------------
  
# =======================================================================

server = new Server()

# =======================================================================

app = express.createServer()

app.get "/:id",  (req,res) -> server.handleGet  req, res
app.post "/:id", (req,res) -> server.handlePost req, res

port = argv.port or argv.p or 3000

app.listen port
