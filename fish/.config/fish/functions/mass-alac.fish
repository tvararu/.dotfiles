function mass-alac
for dir in (ls); cd $dir; alac-it-up; cd ..; end
end
