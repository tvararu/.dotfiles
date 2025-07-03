function randommac --description 'Randomize Wi-Fi MAC address'
    # Turn off Wi-Fi
    sudo networksetup -setairportpower en0 off

    # Generate and set random MAC address
    sudo ifconfig en0 ether (openssl rand -hex 6 | sed "s/../&:/g; s/:\$//")

    # Turn Wi-Fi back on
    sudo networksetup -setairportpower en0 on

    echo "MAC address randomized and Wi-Fi restarted"
end
