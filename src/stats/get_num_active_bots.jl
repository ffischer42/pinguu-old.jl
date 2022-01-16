function get_num_active_bots(u::String="*"; base_path::String=Pinguu.base_dir)
    config_paths = glob(joinpath(base_path, "users/" * u * "/*/config.json"));
    num = 0
    for path in config_paths
        tmp = JSON.parsefile(path)
        num = tmp["status"] != "dead" ? num + 1 : num
    end
    config_paths = glob(joinpath(base_path, "grid_bots/user/" * u * "/*/config.json"));
    for path in config_paths
        tmp = JSON.parsefile(path)
        if tmp["testing"] == "0"
            num = tmp["status"] != "finished" ? num + 1 : num
        end
    end
    return num
end
export get_num_active_bots