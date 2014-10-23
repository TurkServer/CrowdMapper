zerorpc = Npm.require("zerorpc")

client = new zerorpc.Client()
# Try to talk to localhost. If the python service hasn't started, an error
# will be thrown later.
client.connect("tcp://127.0.0.1:4242")

# Print out any errors that might be encountered
client.on "error", (err) -> console.error("RPC client error: ", err)

Analysis =
  invoke: Meteor.wrapAsync(client.invoke, client)

Meteor.defer ->
  console.log "Trying python RPC server..."
  try
    response = Analysis.invoke("maxMatching", [ [0, 0.5], [1, 0.5] ])
    console.log("Got python response (expect 1.5): ", response)
  catch e
    console.error("RPC error: ", e.stack)
