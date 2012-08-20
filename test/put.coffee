
request = require 'request'
url = "http://localhost:3000/"

argv = require('optimist').argv

key = argv.k or argv.key or "themax@gmail.com"
pw = argv.p or argv.password or 'aAbBcCdDeEfF012'

data =
  "foo2.com" :
    security : 7
    length : 12
    symbs : 0
    version : 1
  "bizzle2.com" :
    security : 8
    length : 16
    symbs : 1
    version : 2
    

args =
  url : url + key + "/" + pw
  form :
    data : JSON.stringify data
  
await request.post args, defer e, r, body

if e
  console.log "Error in put: #{e}"
else
  console.log "Success: #{body}"
