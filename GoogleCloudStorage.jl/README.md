# GoogleCloudStorage.jl


[![CI](https://github.com/takuizum/GoogleCloudAPIs.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/takuizum/GoogleCloudAPIs.jl/actions/workflows/CI.yml) [![codecov](https://codecov.io/gh/takuizum/GoogleCloudAPIs.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/takuizum/GoogleCloudAPIs.jl) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](../LICENSE)

Google Cloud Storage JSON API client for Julia. Part of the [GoogleCloudAPIs.jl](../README.md) monorepo.

## Features

- Bucket lifecycle: `list_buckets`, `get_bucket`, `create_bucket`, `delete_bucket`
- Object lifecycle: `list_objects`, `get_object`, `delete_object`
- Single-shot upload (`upload_object`) and download (`download_object`)
- Emulator support via `STORAGE_EMULATOR_HOST` (e.g. `fsouza/fake-gcs-server`)
- Built on top of `GoogleAuth.jl` + `GoogleApiCore.jl`

## Quick start

```julia
using GoogleCloudStorage

client = Client("your-project-id")        # uses ADC

# List buckets
for b in list_buckets(client)
    println("$(b.name) ($(b.location))")
end

# Create + use + delete a bucket
b = create_bucket(client, "my-test-bucket"; location="US")

upload_object(client, "my-test-bucket", "hello.txt", "Hello, world!";
              content_type="text/plain")
data = download_object(client, "my-test-bucket", "hello.txt")
println(String(data))           # "Hello, world!"

delete_object(client, "my-test-bucket", "hello.txt")
delete_bucket(client, "my-test-bucket")
```

## Upload variants

`upload_object` accepts `Vector{UInt8}`, `AbstractString`, or `IO`:

```julia
upload_object(client, "bkt", "bytes.bin",  UInt8[0x01, 0x02])
upload_object(client, "bkt", "text.txt",   "string content"; content_type="text/plain")
upload_object(client, "bkt", "stream.dat", open("local.dat"))
```

## Download variants

```julia
data = download_object(client, "bkt", "key")            # Vector{UInt8}
open("local.dat", "w") do io
    download_object(client, "bkt", "key", io)           # writes to IO, returns nothing
end
```

## Object listing with prefix

```julia
for o in list_objects(client, "bkt"; prefix="logs/2026/")
    println(o.name, " (", o.size, " bytes)")
end
```

## v0.1 limitations

- Simple uploads only (no resumable). Large uploads should be chunked manually.
- No V4 signed URLs (planned for v0.2).

## License

[MIT](LICENSE)
