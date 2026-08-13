# Record and verify install identity

Each installer persists one Install identity and its matching lifecycle adapter
consumes it. Destructive actions operate only on recorded paths and resources
whose Squarebox ownership is verified; fixed names or reconstructed defaults are
insufficient authority. Windows PowerShell and Git Bash keep one closed
`FORMAT=1` field set, but native path and shell-profile values are adapter-owned
and are not cross-consumed.
