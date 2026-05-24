# discovery.jl
module Discovery

using HTTP
using JSON

export generate_api

"""
Fetches the Google Discovery API JSON for a specific service and version.
"""
function fetch_discovery_doc(api_name::String, version::String)
    url = "https://www.googleapis.com/discovery/v1/apis/$api_name/$version/rest"
    resp = HTTP.get(url)
    if resp.status == 200
        return JSON.parse(String(resp.body))
    else
        error("Failed to fetch discovery doc for $api_name $version")
    end
end

"""
Generates a generic REST method string from a discovery resource definition.
This uses metaprogramming concepts to dynamically create function definitions.

For the prototype, it dynamically generates simple HTTP wrapper functions.
"""
function generate_method(service_name::String, resource_name::String, method_name::String, method_def::AbstractDict)
    # The HTTP method (GET, POST, etc)
    http_method = get(method_def, "httpMethod", "GET")
    # The relative path
    path = get(method_def, "path", "")
    
    # Generate a Julia function name, e.g., storage_buckets_get
    func_name = Symbol(join([service_name, resource_name, method_name], "_"))
    
    # Generate the Julia Expression for the function
    expr = quote
        function $(func_name)(client, params::Dict=Dict())
            # Replace path parameters
            url_path = $path
            for (k, v) in params
                placeholder = "{" * string(k) * "}"
                if occursin(placeholder, url_path)
                    url_path = replace(url_path, placeholder => string(v))
                    delete!(params, k)
                end
            end
            
            # Construct the final URL (simplified for prototype)
            # In a real scenario, base URL comes from the discovery root.
            url = "https://$(service_name).googleapis.com/$(url_path)"
            
            # Use the retry logic from GoogleApiCore
            # return do_request_with_retry($http_method, url, headers)
            @info "Executing dynamically generated method: " method=$http_method url=url
            return (;)
        end
    end
    
    return expr
end

"""
Reads a discovery document and evaluates generated methods into the target module.
"""
function generate_api(target_module::Module, api_name::String, version::String)
    doc = fetch_discovery_doc(api_name, version)
    
    if !haskey(doc, "resources")
        @warn "No resources found in discovery doc."
        return
    end
    
    for (res_name, resource) in doc["resources"]
        if haskey(resource, "methods")
            for (meth_name, method_def) in resource["methods"]
                # Generate the expression
                expr = generate_method(api_name, string(res_name), string(meth_name), method_def)
                
                # Evaluate the expression in the target module
                Base.eval(target_module, expr)
            end
        end
    end
    @info "Successfully generated API methods for $api_name v$version in $target_module"
end

end # module Discovery
