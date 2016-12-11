import fnmatch
import os
import re

make_path               = "toolchain/makefile.mak"
src_paths               = ["rtl", "src"]
fileformats             = ["vhdl", "vhd", "c", "cpp"]

vhdl_filename_list      = []
c_filename_list         = []
c_filenames_no_path     = []
blacklist               = ["defines.vhdl", "defines.vhd"]

# Fetch all filenames (with their path) recursively:
found_ctr = 1
for i in range(len(src_paths)):
	for root, dirnames, filenames in os.walk(src_paths[i]):
		for fmt in range(len(fileformats)):
			for filename in fnmatch.filter(filenames, '*.'+fileformats[fmt]):
				if(filename in blacklist):
					continue
				if ".vhd" in filename:
					print str(found_ctr) + "- Found VHDL Source File: " + filename
					vhdl_filename_list.append(os.path.join(root, filename).replace("\\", "/"))
				else:
					print str(found_ctr) + "- Found C/C++ Source File: "	+ filename
					c_filename_list.append(os.path.join(root, filename).replace("\\", "/"))
				found_ctr += 1
# Read entire Makefile:
make_src = ""
with open(make_path, 'r') as content_file:
    make_src = content_file.read()

# Prepare buffer which contains the changes:
# Binaries/Object files:
make_src_new = "BINS = "

for i in range(len(c_filename_list)):
	# Fetch and format filenames:
	filename = c_filename_list[i][c_filename_list[i].index('/')+1 : c_filename_list[i].rindex('.')]
	filename_nopath = filename
	if('/' in filename_nopath):
		filename_nopath = filename[filename.rindex('/')+1:]
	# Push filenames into list:
	#c_filename_list.append(filename)
	c_filenames_no_path.append(filename_nopath)

	# Write binary list for makefile:
	make_src_new += "$(OBJ)/" + filename_nopath + ".o "
	if(i < len(c_filename_list)-1):
		make_src_new += "\\\n\t"
	else:
		make_src_new += "\n\n"

# Rules:
command_template = "\tgcc -c $< -o $@"

for i in range(len(c_filename_list)):
	make_src_new += "$(OBJ)/" + c_filenames_no_path[i] + ".o: ./"+c_filename_list[i] + "\n\t@printf \""+str(i+1)+"- Compiling C file '"+c_filename_list[i]+"': \"\n"+command_template+"\n\n"

# Append temination token:
make_src_new += "#__GENMAKE_END__"

# Make replacements:
make_src = re.sub(r"#__GENMAKE__(?:|\n|^|$|.)+#__GENMAKE_END__", "#__GENMAKE__\n"+make_src_new, make_src)

# Substitute makefile with the new one:
makefile = open(make_path, "wb")
makefile.write(make_src)
makefile.close()

print "Genmake: Makefile updated"