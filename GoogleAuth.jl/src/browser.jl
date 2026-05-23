"""
    open_url(url::AbstractString) -> Bool

Open `url` in the user's default browser. Returns `true` on success.
Falls back silently (returns `false`) if no opener is available — callers
should print the URL for manual copy-paste in that case.
"""
function open_url(url::AbstractString)
    cmd = if Sys.iswindows()
        # `cmd /c start "" URL` — the empty title prevents start from
        # interpreting the URL as a window title.
        `cmd /c start "" $url`
    elseif Sys.isapple()
        `open $url`
    else
        # Linux/BSD: rely on the freedesktop opener.
        `xdg-open $url`
    end
    try
        run(pipeline(cmd; stdout=devnull, stderr=devnull))
        return true
    catch
        return false
    end
end
