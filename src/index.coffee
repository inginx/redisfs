exports.version = '0.1.0'

#
# Sets up a new RedisFs instance.  Generated files and keys
# are tracked so that they can be requested to be deleted at a
# later time via the cleanup of end methods.
#
# options - Optional Hash of options.
#   redis      - Existing instance of node_client.
#   host       - String Redis host.  (Default: Redis' default)
#   port       - Integer Redis port.  (Default: Redis' default)
#   namespace  - String namespace prefix for generated Redis keys.
#                (Default: redisfs).
#   database   - Optional Integer of the Redis database to select.
#   *dir       - Optional path to write files out to for generated files.
#                (Default: your systems temporary directory)
#   prefix     - Optional prefix to use for generated files.  (Default: 'redisfs')
#   suffix     - Optional suffix to use for generated files. 
#   deleteKey  - Optional boolean to indicate if the key should be
#                deleted on a redis2file operation.  (Default: true)
#   deleteFile - Optional boolean to indicate if the file should be
#                deleted on a file2redis operation.  (Default: true)
#
# Note: all params marked as * represent future implementations
#
exports.redisfs = (options) ->
  new exports.RedisFs options

#
# Dependencies
#
_     = require 'underscore'
fs    = require 'fs'
temp  = require 'temp'
uuid  = require 'node-uuid'
redis = require 'redis'
log   = console.log

#
# Option defaults
#
DEFAULTS = 
  deleteKey:  true
  deleteFile: true
  encoding:   'utf8'
  namespace:  'redisfs'
  prefix:     'redisfs-'

#
# Util to pump files in & out of redis.  
#
class RedisFs
  constructor: (options = {}, @keys = [], @files = []) ->
    @config = _.extend _.clone(DEFAULTS), options
    @redis = options.redis or connectToRedis options

  #
  # Pumps a file's contents into a redis key and deletes the file. 
  #   filename     - The full path to the file to consume
  #   options      - Optional options object 
  #     key        - Optional redis key.  If omitted a key will be 
  #                  generated using the default namespace and a uuid.
  #     encoding   - Optional file encoding.
  #     deleteFile - Optional boolean to indicate whether the file file
  #                  should be deleted after it is pumped into redis.
  #   callback     - Recieves either an error as the first param
  #                  or success hash that contains the key and reply
  #                  as the second param.
  #
  file2redis: (filename, options..., callback) ->
    options = @applyConfig options
    fs.readFile filename, options.encoding, (err, data) =>
      if err? then callback err 
      else 
        @set options.key or @key(), data, callback
        @deleteFiles [_.remove filename, @files] if options.deleteFile is on

  #
  # Pumps a redis value to a file and deletes the redis key.
  #   key         - The redis key to fetch.
  #   options     - Optional options object.
  #     filename  - Optional filename to write to. assumes the file is
  #                 preexisting and writable.  If ommitted a temp file 
  #                 will be generated.
  #     encoding  - Optional file encoding, defaults to utf8
  #                 This overrides the instance level options if specified.
  #     *dir      - Optional path to write files out to for generated files.
  #                 This overrides the instance level options if specified.
  #     prefix    - Optional prefix to use for generated files.
  #                 This overrides the instance level options if specified.
  #     suffix    - Optional suffix to use for generated files. 
  #                 This overrides the instance level options if specified.
  #     deleteKey - Optional boolean to indicate if the key should be
  #                 removed after the get operation.  (Default: to value
  #                 set on instance)
  #   callback    - Receives the and error as the first param
  #                 or a success hash that contains the path
  #                 and a fd to the file.
  #
  # Note: all params marked as * represent future implementations
  #
  redis2file: (key, options..., callback) ->
    options = @applyConfig options
    if options.filename?
      @get key, (err, value) =>
        if err? then callback err 
        else
          @write options.filename, value, options.encoding, callback
          @deleteKeys _.remove key, @keys if options.deleteKey is on
    else
      @open key, options, callback

  #
  # Delete generated resources.
  #   options - Optional object indicating which generated resources to 
  #             delete (keys and/or files). Omission of options will result
  #             in the deletion of both files and keys.
  #     keys  - Optional boolean indicating whether files should be
  #             deleted.
  #     files - Optional boolean indicating whether generated files 
  #             should be deleted.
  #
  cleanup: (options) ->
    both   = on unless options?
    both or= options.keys and options.files
    keys   = if both then on else options.keys  or off
    files  = if both then on else options.files or off

    @deleteKeys()  if keys
    @deleteFiles() if files

  #
  # End the redis connection and deletes all the resources generated during
  # the session.  Accepts the same args as cleanup.  To disable the cleanup
  # pass false. 
  #
  end: (options) ->
    @cleanup options unless options is off
    @redis.quit()

  #
  # @private
  # Fets the value of the key.  Callback will be passed the value.
  #
  get: (key, callback) ->
    @redis.get key, (err, value) =>
      callback err, value

  #
  # @private
  # Sets the value to a new redis key.  Callback will be passed
  # a result object containing the key and the redis reply.
  #
  set: (key, value, callback) ->
    @redis.set key, value, (err, reply) =>
      if err? then callback err 
      else 
        callback null, {key: key, reply: reply}

  #
  # @private
  # Generate a new redis key
  #
  key: ->
    @keys.push key = "#{@config.namespace}:#{uuid()}"
    key       

  #
  # @private
  # Pumps a redis value into a generated temp file. Callback will
  # receive the filename.
  #
  open: (key, options, callback) ->
    temp.open {prefix: options.prefix, suffix: options.suffix}, (err, file) =>
      if err? then callback err
      else
        @files.push options.filename = file.path
        @redis2file key, options, callback

  #
  # @private
  # Overlayed the options onto the @config to create the 
  # superset of options with the appropriate defaults.  
  #
  applyConfig: (options) ->
    _.extend _.clone(@config), options[0]

  #
  # @private 
  # Write to a file
  #
  write: (filename, value, encoding, callback) ->
    fs.writeFile filename, value, encoding, (err) =>
      callback err, filename

  #
  # @private
  # Delete all the generated keys in a multi op.  Errors are ignored.
  #
  deleteKeys: (keys = @keys) ->
    if _.isArray keys
      multi = @redis.multi()
      multi.del key for key in keys
      multi.exec()
      @keys = [] if @keys is keys
    else
      @redis.del keys
    
  #
  # @private
  # Delete all the generated files.  Errors are ignored.
  #
  deleteFiles: (files = @files) ->
    fs.unlink file for file in files
    @files = [] if @files is files

#
# Construct a redis client.
#
connectToRedis = (options) ->
  client = redis.createClient options.port, options.host
  client.select options.database if options.database?
  client

#
# _ expando. Remove any element in an array and compact it.  Similar to without
# but done inline.  Returns the passed value.
#
_.remove = (value, array) ->
  index = array.indexOf value
  if index
    swap = array.pop()
    array[index] = swap unless swap is value
  value

exports.RedisFs = RedisFs