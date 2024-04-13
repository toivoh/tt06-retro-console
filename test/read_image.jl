using DelimitedFiles
using ImageView
using ColorTypes
using Test

data = readdlm("vga-data.txt", Int)
avhsync = data[:, 1]
rgb0 = data[:, 2]
rgb = [RGB{Float32}((d>>4)&3/3.0, (d>>2)&3/3.0, (d>>0)&3/3.0) for d in rgb0]

avhsync0 = copy(avhsync)
avhsync0[avhsync0 .== -1] .= 0

active = Bool.((avhsync0 .>> 2) .& 1)


rise = findall(diff(active) .== 1)
fall = findall(diff(active) .== -1)

# Test that we start and stop when active is low
@test length(rise) == length(fall)

hperiod = rise[2] - rise[1]
width = fall[1] - rise[1]
@test all(diff(rise) .== hperiod)
@test all(diff(fall) .== hperiod)
@test all((fall .- rise) .== width)

rgb1 = reshape(rgb[active], (width, :))'
#height = length(rgb1) ÷ width
imshow(rgb1)

nothing
