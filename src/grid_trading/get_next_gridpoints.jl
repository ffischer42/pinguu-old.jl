function get_next_gridpoints(trade_grid, price)
    k = sort(string.(keys(trade_grid)))
    index = findall(x->x == price, k)[1]
    result = Dict()
    if index > 1
        result["BUY"] = k[index-1]
    end
    if index < length(k)
        result["SELL"] = k[index+1]
    end
    return result
end
export get_next_gridpoints