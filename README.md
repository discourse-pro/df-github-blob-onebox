The plugin improves the [built-in GitHub Blob Onebox](https://github.com/discourse/onebox/blob/v1.8.33/lib/onebox/engine/github_blob_onebox.rb#L1-L210):

- It [removes the limitation for the maximum number of code lines](https://meta.discourse.org/t/42321)
- It provides the `df:refresh_oneboxes[<delay in seconds>]` rake task, which allows to make delays between posts refreshment to overcome GitHub rate limits. 

