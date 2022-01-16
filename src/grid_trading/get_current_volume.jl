function get_current_volume(config)
    current_volume = typeof(config["total_value"]) == Float64 ? config["total_value"] : parse(Float64, config["total_value"])
    if length(config["extra_volume"]) > 0
        for (k,v) in config["extra_volume"]
            current_volume += v
        end
    end
    current_volume += config["thes_volume"]
    return current_volume
end
export get_current_volume