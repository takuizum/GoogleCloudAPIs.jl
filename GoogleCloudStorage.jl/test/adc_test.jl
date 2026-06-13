using Test
using GoogleCloudStorage
using GoogleAuth

@testset "Automatic ADC loading in Client" begin
    # Mock ADC JSON
    adc_json = """
    {
        "type": "authorized_user",
        "client_id": "test-client-id",
        "client_secret": "test-client-secret",
        "refresh_token": "test-refresh-token"
    }
    """
    path = tempname() * ".json"
    write(path, adc_json)

    # Point ADC at the mock file, and clear STORAGE_EMULATOR_HOST so the
    # client does not short-circuit into emulator mode (CI sets it).
    old_adc = get(ENV, "GOOGLE_APPLICATION_CREDENTIALS", nothing)
    old_emu = get(ENV, "STORAGE_EMULATOR_HOST", nothing)
    ENV["GOOGLE_APPLICATION_CREDENTIALS"] = path
    delete!(ENV, "STORAGE_EMULATOR_HOST")

    try
        # Create client without explicit credentials
        client = Client("test-project")

        @test client.creds !== nothing
        @test client.creds isa CachedCredentials
        @test client.creds.inner isa UserCredentials
        @test client.creds.inner.client_id == "test-client-id"
        @test client.creds.inner.refresh_token == "test-refresh-token"
        @test client.is_emulator == false
        @test client.endpoint == "https://storage.googleapis.com"

    finally
        # Cleanup
        if old_adc === nothing
            delete!(ENV, "GOOGLE_APPLICATION_CREDENTIALS")
        else
            ENV["GOOGLE_APPLICATION_CREDENTIALS"] = old_adc
        end
        if old_emu !== nothing
            ENV["STORAGE_EMULATOR_HOST"] = old_emu
        end
        rm(path)
    end
end
