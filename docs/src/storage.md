# [Cloud Storage API](@id storage)

`GoogleCloudStorage` wraps the [GCS JSON API](https://cloud.google.com/storage/docs/json_api).

## Client

```@docs
GoogleCloudStorage.Client
```

### Emulator

Set `STORAGE_EMULATOR_HOST=http://localhost:4443` (or any `http://` URL) before
constructing a `Client` and it will skip authentication automatically.

## Bucket operations

```@docs
GoogleCloudStorage.Bucket
GoogleCloudStorage.list_buckets
GoogleCloudStorage.get_bucket
GoogleCloudStorage.create_bucket
GoogleCloudStorage.delete_bucket
```

## Object operations

```@docs
GoogleCloudStorage.Object
GoogleCloudStorage.list_objects
GoogleCloudStorage.get_object
GoogleCloudStorage.download_object
GoogleCloudStorage.upload_object
GoogleCloudStorage.delete_object
```

## Example

```julia
import GoogleCloudStorage

gcs = GoogleCloudStorage.Client("my-project")

# Bucket lifecycle
bucket = GoogleCloudStorage.create_bucket(gcs, "my-bucket"; location="US")
println(bucket.name)

# Upload / download
GoogleCloudStorage.upload_object(gcs, "my-bucket", "hello.txt", "Hello World!")
bytes = GoogleCloudStorage.download_object(gcs, "my-bucket", "hello.txt")
println(String(bytes))   # "Hello World!"

# List objects under a prefix
for obj in GoogleCloudStorage.list_objects(gcs, "my-bucket"; prefix="logs/")
    println(obj.name, "  ", obj.size, " bytes")
end

# Clean up
GoogleCloudStorage.delete_object(gcs, "my-bucket", "hello.txt")
GoogleCloudStorage.delete_bucket(gcs, "my-bucket")
```
