# manual_browser_auth_test.jl
#
# このスクリプトは、ブラウザを使用して対話的に Google Cloud 認証を行うためのものです。
#
# 【事前準備】
# 1. Google Cloud Console (https://console.cloud.google.com/apis/credentials) で
#    「OAuth 2.0 クライアント ID」（種類：デスクトップ アプリ）を作成してください。
# 2. 作成したクライアントの JSON ファイルをダウンロードするか、
#    Client ID と Client Secret を控えておいてください。
#
# 【実行方法】
# 以下のいずれかの方法で認証情報を渡してください：
# A. .env ファイルに記述する（プロジェクトルートまたはこのファイルと同じディレクトリ）:
#    GOOGLE_AUTH_CLIENT_ID=xxxx
#    GOOGLE_AUTH_CLIENT_SECRET=yyyy
#
# B. 環境変数として渡す:
#    export GOOGLE_AUTH_CLIENT_ID=xxxx
#    export GOOGLE_AUTH_CLIENT_SECRET=yyyy
#
# C. クライアントシークレットの JSON ファイルを指定する:
#    export GOOGLE_AUTH_CLIENT_SECRET_FILE=path/to/client_secret.json
#
# ※ 注意: すでに `gcloud auth application-default login` を済ませている場合は、
#    通常はこのスクリプトを実行する必要はありません。各クライアント（BQClient 等）は
#    自動的にその認証情報を読み込みます。

using GoogleAuth
using JSON

# Simple .env loader
function load_env(path)
    if isfile(path)
        for line in eachline(path)
            line = strip(line)
            if isempty(line) || startswith(line, "#")
                continue
            end
            m = match(r"^([^=]+)=(.*)$", line)
            if m !== nothing
                key = strip(m.captures[1])
                val = strip(m.captures[2])
                if (startswith(val, "\"") && endswith(val, "\"")) ||
                   (startswith(val, "'") && endswith(val, "'"))
                    val = val[2:end-1]
                end
                ENV[key] = val
            end
        end
    end
end

# Load .env from script directory or project root
load_env(joinpath(@__DIR__, ".env"))
load_env(joinpath(@__DIR__, "..", "..", ".env"))

function first_env(names...)
    for name in names
        value = get(ENV, name, "")
        isempty(value) || return value
    end
    return ""
end

function load_client_credentials()
    json_path = first_env("GOOGLE_AUTH_CLIENT_SECRET_FILE",
        "GOOGLE_CLIENT_SECRET_FILE")

    if !isempty(json_path)
        data = JSON.parse(read(json_path, String))
        if haskey(data, "installed")
            return String(data["installed"]["client_id"]), String(data["installed"]["client_secret"])
        elseif haskey(data, "web")
            return String(data["web"]["client_id"]), String(data["web"]["client_secret"])
        else
            error("Client secret JSON must contain an `installed` or `web` object")
        end
    end

    client_id = first_env("GOOGLE_AUTH_CLIENT_ID", "GOOGLE_CLIENT_ID")
    client_secret = first_env("GOOGLE_AUTH_CLIENT_SECRET", "GOOGLE_CLIENT_SECRET")

    if isempty(client_id)
        error("Set GOOGLE_AUTH_CLIENT_ID or point GOOGLE_AUTH_CLIENT_SECRET_FILE to a client secret JSON.\n" *
              "Create one at: https://console.cloud.google.com/apis/credentials")
    end

    return client_id, client_secret
end

client_id, client_secret = load_client_credentials()
open_browser = lowercase(get(ENV, "GOOGLE_AUTH_OPEN_BROWSER", "true")) != "false"
save_adc = lowercase(get(ENV, "GOOGLE_AUTH_SAVE_ADC", "false")) == "true"
timeout = parse(Int, get(ENV, "GOOGLE_AUTH_TIMEOUT", "300"))

println("Starting browser authentication...")
println("Client ID: ", client_id)
println("Complete the login in the browser window that opens.")

creds = authorize_via_browser(;
    client_id=client_id,
    client_secret=client_secret,
    scopes=["https://www.googleapis.com/auth/cloud-platform"],
    open_browser=open_browser,
    save_adc=save_adc,
    timeout=timeout,
)

println("\nAuthentication completed.")
println("Credential type: ", typeof(creds))
println("Auth Header: ", authorization_header(creds))

if save_adc
    println("ADC has been saved to the well-known location.")
else
    println("Note: Credentials are in memory only. Use GOOGLE_AUTH_SAVE_ADC=true to persist.")
end
