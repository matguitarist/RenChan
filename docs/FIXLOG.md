# RenChan — Fix log

## 2026-11-22 A download that isn't a zip showed unzip's raw error

Dropping `cosy-cafe-mac.zip` showed several lines of zipinfo output. The file was 118 bytes of XML: itch.io's download links expire after 60 seconds, and Safari saved the "Request has expired" error page under the zip's name. RenChan now checks the zip signature (PK) before asking to unpack, and says the file isn't a zip, its size, and to download again.
Test: `aDownloadThatIsntAZipIsRefusedPlainly` in LocatorTests.
Rule: check what a file is by its first bytes before handing it to a tool, and turn a tool's raw error into what happened and what to do.
