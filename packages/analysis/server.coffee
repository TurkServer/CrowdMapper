zerorpc = Npm.require("zerorpc")

client = new zerorpc.Client()
# Try to talk to localhost. If the python service hasn't started, an error
# will be thrown later.
client.connect("tcp://127.0.0.1:4242")

# Print out any errors that might be encountered
client.on "error", (err) -> console.error("RPC client error: ", err)

invokeSync = Meteor.wrapAsync(client.invoke, client)

class Analysis
