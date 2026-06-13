using Pkg

const PACKAGES = [
    "GoogleAuth",
    "GoogleApiCore",
    "GoogleCloudStorage",
    "GoogleBigQuery",
    "GoogleCloudPubSub"
]

for pkg in PACKAGES
    println("="^60)
    println("Testing $pkg ...")
    println("="^60)
    Pkg.test(pkg)
end
