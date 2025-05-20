function ffmpeg --description 'Run ffmpeg in a docker container'
    if not command -q docker
        echo "Docker is not installed"
        return 1
    end

    set -l container_name ffmpeg_temp
    set -l image_name "jrottenberg/ffmpeg:4.4-ubuntu"

    # Pull image if not exists
    if not docker image inspect $image_name >/dev/null 2>&1
        docker pull $image_name
    end

    # Run ffmpeg with proper argument handling
    docker run --rm \
                -v (pwd):/workdir \
                -w /workdir \
                --name $container_name \
                $image_name \
                $argv
end
