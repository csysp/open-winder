Optional security scanners (lynis, rkhunter, chkrootkit, clamav) are disabled by default.

Enable by setting `SECURITY_SCANNERS_ENABLE=true` in `home-secnet/.env` and running:

  make security-enable

Timers run daily with randomized delays. Logs are under `/var/log` as created by the scripts.
