using DelimitedFiles
using Plots

data = readdlm("event-data.txt", Int)
source = data[:, 1]
streams = [data[data[:, 1] .== i,2:3] for i = 0:4]

function plot_streams(streams)
	for (i, stream) in enumerate(streams[1:4])
		pl = i == 1 ? plot : plot!
		display(pl(stream[:,1], stream[:,2]))
	end

	out = streams[5][:,2]
	out_t = (0:length(out)-1)*32

	display(plot!(out_t, 32*out, color=:black))
end

plot_streams(streams)
