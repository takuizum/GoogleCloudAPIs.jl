module GoogleAuth

using HTTP
using JSON3
using StructTypes
using Dates
using JSONWebTokens
using URIs
import Base64
import Random
import SHA
import Sockets

export Credentials, Token, ServiceAccountCredentials, UserCredentials, ComputeCredentials
export ImpersonatedCredentials, CachedCredentials
export get_application_default, get_token, authorization_header
export with_scopes
export authorize_via_browser, open_url

include("credentials.jl")
include("metadata.jl")
include("adc.jl")
include("browser.jl")
include("oauth.jl")

end # module GoogleAuth
