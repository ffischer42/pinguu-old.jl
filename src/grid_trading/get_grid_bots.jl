function get_grid_bots(base_path::String=Pinguu.base_dir, api_path::String=ENV["api"])
    config_files = glob(joinpath(base_path, "grid_bots/user/*/*/config.json"))
    api = JSON.parsefile(api_path)
    telegram = JSON.parsefile(joinpath(base_path, "telegram.json"))
    dev_settings = JSON.parsefile(joinpath(base_path, "dev.json"))
    config_paths = []
    clients = []
    user = []
    for file in config_files
        tmp = JSON.parsefile(file)
        if !(tmp["status"] in ["dead", "finished"])
            bot_path = joinpath("/", dirname(file))
            user_id = string(tmp["user_id"])
            if haskey(api, user_id)
                push!(clients, binance.Client(api[user_id]["api"], api[user_id]["api_secret"]))
                push!(config_paths, bot_path)
            end
            tmp_usr = Dict()
            tmp_usr["user_id"] = user_id
            if haskey(telegram, user_id)
                tmp_usr["telegram"] = telegram[user_id]
            else
                tmp_usr["telegram"] = ""
            end
            push!(user, tmp_usr)
        end
    end
    return config_paths, clients, user
end
export get_grid_bots