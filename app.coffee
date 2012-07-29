express = require "express"
argv = require('optimist').argv
dynamo = require 'dynamo'

# =======================================================================
class Server
  constructor : () ->
    @_cache = {}
    @_client = dynamo.createClient()
    @_db = @_client.get("us-east-1")
    @_tb = "1sp_public_data"

  handleGet : (req, res) ->
    id = req.params.id
    await
      @_db.get(@_tb).query({key : id }).get("data").fetch defer err, data

server = new Server()

# =======================================================================

app = express.createServer()

app.get "/:id",  (req,res) -> server.handleGet  req, res
app.post "/:id", (req,res) -> server.handlePost req, res

port = argv.port or argv.p or 3000

app.listen port
