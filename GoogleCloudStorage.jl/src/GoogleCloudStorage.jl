module GoogleCloudStorage

using HTTP
using JSON3
using StructTypes
using URIs

import GoogleAuth
import GoogleApiCore

export Client, Bucket, Object
export list_buckets, get_bucket, create_bucket, delete_bucket
export list_objects, get_object, download_object, upload_object, delete_object

include("client.jl")
include("buckets.jl")
include("objects.jl")

end # module GoogleCloudStorage
