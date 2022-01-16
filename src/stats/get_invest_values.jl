function get_invest_values(u::String="*")
    invest_then = 0
    invest_now  = 0
    invest_paths = glob(joinpath(Pinguu.base_dir[2:end], "stats/users/" * u * "/invest.json"))
    for path in invest_paths
        tmp = JSON.parsefile(path)
        for (symbol, stat) in tmp
            invest_then += stat["value"]
            invest_now  += stat["value_now"]
        end
    end
    return invest_then, invest_now
end
return get_invest_values