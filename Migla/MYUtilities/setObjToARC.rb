#! /usr/bin/env ruby

if ARGV.length == 0
    puts "Usage: setObjToARC sourcefile ..."
    puts ""
    puts "Modifies input files in-place, updating setObj() calls to ARC-convertable equivalents"
    exit 0
end

ARGV.each do |filename|
    puts "#{filename} ..."
    outfilename = filename + ".temp"
    File.open(outfilename, "w") do |out|
        IO.foreach(filename) do |line|
        	line.gsub!(/\bsetObj\(&(\w+),(.*)\);/,	'(void)[\1 autorelease]; \1 = [\2 retain];')
        	line.gsub!(/\bsetObjCopy\(&(\w+),(.*)\);/,	'(void)[\1 autorelease]; \1 = [\2 copy];')
        	line.gsub!(/\[nil (retain|copy)\]/,	'nil')
        	line.gsub!(/\bifSetObj\(&(\w+),(.*)\);/,	'!$equal(\1, \2) && ((void)[\1 autorelease], \1 = [\2 retain], YES)')
        	line.gsub!(/\bifSetObjCopy\(&(\w+),(.*)\);/,	'!$equal(\1, \2) && ((void)[\1 autorelease], \1 = [\2 copy], YES)')
        	out.puts line
        end
    end
    File.rename(outfilename, filename)
end
