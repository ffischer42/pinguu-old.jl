module Pinguu

using CSV
using DataFrames
using Dates
using Format
using Glob
using HTTP
using Indicators
using JSON
using Telegram, Telegram.API
using PyCall
using Query
using StatsBase
using Suppressor
using TypedTables
binance = pyimport("binance.client");
export binance


include("api/check_orders.jl")
include("api/check_why_there_is_no_sell.jl")
include("api/determine_closed.jl")
include("api/examine_order.jl")
include("api/place_order_command.jl")
include("api/trade.jl")
include("api/trade_helper.jl")
include("api/buy_helper.jl")
include("api/BNB_control.jl")
include("api/get_current_ticker.jl")

include("analysis/check_balances.jl")
include("analysis/convert.jl")
include("analysis/ema.jl")
include("analysis/klines.jl")
include("analysis/trigger.jl")
include("analysis/calc_order_fee.jl")
include("analysis/create_tax_report.jl")

include("interface/history.jl")
include("interface/notification.jl")

include("invest/cancel_invest.jl")
include("invest/check_liquid.jl")
include("invest/move_order_to_invest.jl")
include("invest/move_to_filled.jl")
include("invest/place_invest.jl")

include("tasks/scanner.jl")

include("stats/stats_fct.jl")
include("grid_trading/grid_trading.jl")


# Analysis export
export convert_klines, get_ema
export get_trigger_limits, place_triggers

# API export
export buy_coin_and_place_sell, buy_coin_and_place_sell_test, check_open_orders
export place_first_order!, check_open_sell!, check_open_buy!
export place_first_poly_order!, check_open_poly_sell!, check_open_poly_buy!

const base_dir = ENV["pinguu"]
const telegram = ENV["telegram"]
export base_dir
export telegram

end