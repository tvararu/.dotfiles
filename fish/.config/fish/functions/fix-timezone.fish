function fix-timezone
sudo timedatectl set-timezone (curl --fail https://ipapi.co/timezone)
end
