using Pkg

const PACKAGES = [
    "GoogleAuth",
    "GoogleApiCore",
    "GoogleCloudStorage",
    "BigQuery",
    "GoogleCloudPubSub"
]

for pkg in PACKAGES
    println("="^60)
    println("Testing $pkg ...")
    println("="^60)
    Pkg.test(pkg)
end
