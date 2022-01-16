function create_overview_stats(u::String; base_path::String=joinpath(Pinguu.base_dir[2:end], "stats/"))
    eval_date = string(today())
    invest_then, invest_now = Pinguu.get_invest_values(u)
    past_days, profits_daily = Pinguu.get_profit_for_past_days(u, 90)
    past_months, profits_monthly = Pinguu.get_profit_for_past_months(u, 24)
    overview = Dict(
        "bot_profit"  => Pinguu.get_total_profit(u),
        "bot_profit_today" => Pinguu.get_profit_for_single_day(u, eval_date),
        "active_bots" => Pinguu.get_num_active_bots(u),
        "bot_volume"  => Pinguu.get_total_bot_volume(u),
        "invest_then" => invest_then,
        "invest_now"  => invest_now,
        "past_days"   => past_days,
        "profits_daily" => profits_daily,
        "past_months"   => past_months,
        "profits_monthly" => profits_monthly
    )
    if u != "*"
        filename = joinpath(base_path, "users/" * u * "/profits.json")
    else
        filename = joinpath(base_path, "all_profits.json")
    end
    !isdir(dirname(filename)) ? mkpath(dirname(filename)) : ""
    open(filename, "w") do f
        JSON.print(f, overview, 4)
    end
end
export create_overview_stats