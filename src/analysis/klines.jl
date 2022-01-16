function convert_klines(klines)
    t     = []
    start = []
    high  = []
    low   = []
    out   = []
    for i in 1:1:size(klines,1)
        push!(t, unix2datetime(klines[i, 7]/1000))
        push!(start, parse(Float64, klines[i,2]))
        push!(high, parse(Float64, klines[i,3]))
        push!(low, parse(Float64, klines[i,4]))
        push!(out, parse(Float64, klines[i,5]))
    end
    return t, out, high, low
end

function klines2table(klines; time_warp=3600)
    open_time  = []
    open       = []
    high       = []
    low        = []
    close      = []
    volume     = []
    close_time = []
    for i in 1:1:size(klines,1)
        push!(open_time, unix2datetime(klines[i, 1]/1000 + time_warp))
        push!(open, parse(Float64, klines[i,2]))
        push!(high, parse(Float64, klines[i,3]))
        push!(low, parse(Float64, klines[i,4]))
        push!(close, parse(Float64, klines[i,5]))
        push!(volume, parse(Float64, klines[i,6]))
        push!(close_time, unix2datetime(klines[i, 7]/1000 + time_warp))
    end
    return Table(
        open_time = Array{DateTime,1}(open_time), 
        open = Array{Float64,1}(open),
        high = Array{Float64,1}(high),
        low = Array{Float64,1}(low),
        close = Array{Float64,1}(close),
        close_time = Array{DateTime,1}(close_time)
    )
end

function get_klines(client, symbol, kline, datapoints; time_warp=3600)
    timespans = Dict()
    timespans["1m"] = [1, "minute"]
    timespans["3m"] = [3, "minute"]
    timespans["5m"] = [5, "minute"]
    timespans["15m"] = [15, "minute"]
    timespans["30m"] = [30, "minute"]

    timespans["1h"] = [1, "hour"]
    timespans["2h"] = [2, "hour"]
    timespans["4h"] = [4, "hour"]
    timespans["6h"] = [6, "hour"]
    timespans["8h"] = [8, "hour"]
    timespans["12h"] = [12, "hour"]

    timespans["1d"] = [1, "day"]
    timespans["3d"] = [3, "day"]

    timespans["1w"] = [1, "week"]

    timespans["1M"] = [1, "month"]
    kline_type = split(kline, "_")[end]
    kline_historical = string(datapoints * timespans[kline_type][1]) * " " * timespans[kline_type][2]
    sleep(2)
    klines = client.get_historical_klines(symbol, kline_type, kline_historical * " ago UTC");
    return Pinguu.klines2table(klines; time_warp=time_warp)
end