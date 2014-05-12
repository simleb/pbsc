#!/usr/bin/env ruby

# Copyright (c) 2013 Simon Leblanc
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

require 'curses'
require 'yaml'


$fields = {
	:id        => { :name =>          'Job ID', :width => 7 },
	:name      => { :name =>        'Job name', :width => {:min => 8, :weight => 1} },
	:procs     => { :name =>           'Procs', :width => 5 },
	:walltime  => { :name =>        'Walltime', :width => 12 },
	:elapsed   => { :name =>    'Elapsed time', :width => 12 },
	:remaining => { :name =>       'Remaining', :width => 12 },
	:efficacy  => { :name =>        'Efficacy', :width => 6 },
	:xfactor   => { :name =>        'X factor', :width => 4 },
	:rank      => { :name =>            'Rank', :width => 7 },
	:start     => { :name =>      'Start time', :width => 20 },
	:queue     => { :name =>      'Queue time', :width => 20 },
	:estimated => { :name => 'Est. start time', :width => 20 },
	:stop      => { :name => 'Completion time', :width => 20 },
	:state     => { :name =>           'State', :width => 8 },
	:reason    => { :name =>          'Reason', :width => {:min => 20, :weight => 2} },
	:exit      => { :name =>     'Exit status', :width => 5 },
	:user      => { :name =>        'Username', :width => 8 },
	:group     => { :name =>           'Group', :width => 8 },
	:class     => { :name =>           'Queue', :width => 8 },
	:priority  => { :name =>        'Priority', :width => 5 },
}

$display = {
	:completed => [:id, :name, :procs, :exit, :elapsed, :efficacy],
	:running   => [:id, :name, :procs, :remaining, :efficacy, :start],
	:idle      => [:id, :name, :procs, :rank, :estimated, :xfactor],
	:blocked   => [:id, :name, :procs, :walltime, :state]
}


def init
	ENV['ESCDELAY'] = 0.to_s # no delay when pressing escape
	Curses.init_screen
	Curses.noecho # do not show typed keys
	Curses.cbreak # disable line buffering
	Curses.curs_set(0) # hide cursor
	Curses.stdscr.keypad(true) # enable arrow keys
	Curses.start_color
	Curses.init_pair(1, 253, 0); # completed odd
	Curses.init_pair(2,  15, 0); # completed even
	Curses.init_pair(3,  40, 0); # running odd
	Curses.init_pair(4,  46, 0); # running even
	Curses.init_pair(5, 220, 0); # idle odd
	Curses.init_pair(6, 226, 0); # idle even
	Curses.init_pair(7, 160, 0); # blocked odd
	Curses.init_pair(8, 196, 0); # blocked even
	$colors = {
		:completed => [1, 2],
		:running   => [3, 4],
		:idle      => [5, 6],
		:blocked   => [7, 8]
	}
	$cols = {} # Number of columns left for flexible columns for each status
	$flex = {} # Sum of weights for each status
	begin
		yield
	ensure
		Curses.close_screen
	end
end


def printText(line, text, style=nil)
	# Print full-width left-aligned text
	Curses.setpos(line % Curses.lines, 0)
	Curses.attron(Curses::A_REVERSE) if style == :highlight
	w = Curses.cols - 2
	Curses.addstr(" %-#{w}.#{w}s " % text)
	Curses.attroff(Curses::A_REVERSE) if style == :highlight
end


def width(status, key, i)
	# Helper for flexible-width columns
	w = $fields[key][:width]
	if w.is_a? Hash
		carry = i < ($cols[status] % $flex[status]) ? 1 : 0
		w = [w[:min], $cols[status] * w[:weight] / $flex[status] + carry].max
	end
	w
end


def printHeader(line, status)
	# Print header for a given status
	Curses.setpos(line % Curses.lines, 0)
	count = 0
	$display[status].each_with_index do |key, i|
		w = width(status, key, i)
		break if count + w + 2 > Curses.cols
		Curses.attron(Curses::A_REVERSE)
		Curses.addstr(" %#{w}.#{w}s " % $fields[key][:name])
		Curses.attroff(Curses::A_REVERSE)
		count += w + 2
	end
end


def printJob(line, job, style=nil)
	# Print a job with color matching its status
	Curses.setpos(line % Curses.lines, 0)
	status = job[:status]
	count = 0
	$display[status].each_with_index do |key, i|
		w = width(status, key, i)
		break if count + w + 2 > Curses.cols
		color = $colors[status][i % $colors[status].length]
		Curses.attron(Curses::A_REVERSE) if style == :highlight
		Curses.attron(Curses.color_pair(color))
		Curses.addstr(" %#{w}.#{w}s " % job[key])
		Curses.attroff(Curses.color_pair(color))
		Curses.attroff(Curses::A_REVERSE) if style == :highlight
		count += w + 2
	end
end


def printStatus(message)
	# Print a status message (last row)
	printText(-1, message, :highlight)
end


def display(jobs, selection)
	# Display the job list
	Curses.clear
	printStatus('Press H or ? for help, Q or ESC to quit.')
	if jobs.empty?
		printText(0, 'No jobs in the queue. Press R to refresh.')
		return
	end

	$display.each do |status, keys|
		$cols[status] = Curses.cols
		$flex[status] = 0
		keys.each do |key|
			if $fields[key][:width].is_a? Hash
				$cols[status] -= 2
				$flex[status] += $fields[key][:width][:weight]
			else
				$cols[status] -= $fields[key][:width] + 2
			end
		end
	end

	line = 0
	# FIXME: ordering is not garanteed for Hashes. Should use order from $display
	jobs.group_by { |job| job[:status] }.each do |status, subjobs|
		printHeader(line, status)
		line += 1
		subjobs.each do |job|
			printJob(line, job, (:highlight if job[:id] == selection))
			line += 1
		end
		line += 1
	end
end


def help
	# Display the help page
	Curses.clear
	printText(0, 'List of commands - Press any key to go back', :highlight)
	printText(2, '  H or ?        Display this help page')
	printText(3, '  Q or ESC      Quit')
	printText(5, '  Up/Down       Highlight previous/next job')
	printText(6, '  Enter/Space   Display more information about the highlighted job')
	printText(7, '  R             Refresh the list of jobs')
	Curses.getch
end


def details(jobs, selection)
	# Display the details page of the currently selected job
	# Calls checkjob to get complete info about the job.
	return unless selection
	return unless job = jobs.find { |job| job[:id] == selection }

	Curses.clear
	printText(0, 'Job details - Press any key to go back', :highlight)

	# Run checkjob to get more info
	prog = <<-END_AWK
		/^AName:/ { print ":name:", substr($0, index($0, $2)); }
		/^WallTime:/ {
			print ":elapsed: \\"" $2 "\\"";
			print ":walltime: \\"" $4 "\\"";
		}
		/^State:/ { print ":state: :" tolower($2); }
		/^Creds:/ {
			print ":group:", substr($3, index($3, ":") + 1);
			print ":class:", substr($4, index($4, ":") + 1);
		}
		/^SubmitTime:/ { print ":queue:", substr($0, index($0, $2)); }
		/^StartTime:/ { print ":start:", substr($0, index($0, $2)); }
		/^Reserved Nodes:/ { print ":estimated: \\"" substr($3, index($3, "(") + 1) "\\""; }
		/^StartPriority:/ { print ":priority:", $2; }
		/^BLOCK MSG:/ { print ":reason: \\"" substr($0, index($0, $3)) "\\""; }
	END_AWK
	job.merge!((YAML.load `checkjob #{job[:id]} | awk '#{prog}'`) || {})

	l = 1
	printText(l += 1, "Job ID: #{job[:id]}")
	printText(l += 1, "Job name: #{job[:name]}")
	printText(l += 1, "Number of procs: #{job[:procs]}")
	printText(l += 1, "Walltime limit: #{job[:walltime]}")

	color = $colors[job[:status]][0]
	Curses.attron(Curses.color_pair(color))
	printText(l += 2, "Status: #{job[:status].to_s.capitalize}")
	Curses.attroff(Curses.color_pair(color))

	l += 1
	(job.keys - [:id, :name, :procs, :walltime, :status]).each do |key|
		printText(l += 1, "#{$fields[key][:name]}: #{job[key]}")
	end

	Curses.getch
end


def nextJob(jobs, selection)
	# Selects the next job in the list with wrap around (or select the first job)
	return nil if jobs.empty?
	if selection
		i = jobs.find_index { |job| job[:id] == selection }
		return jobs[(i+1) % jobs.length][:id]
	else
		return jobs.first[:id]
	end
end


def prevJob(jobs, selection)
	# Selects the previous job in the list with wrap around (or select the last job)
	return nil if jobs.empty?
	if selection
		i = jobs.find_index { |job| job[:id] == selection }
		return jobs[(i-1) % jobs.length][:id]
	else
		return jobs.last[:id]
	end
end


def getJobs
	# Load and parse the jobs of the current user from the queue
	# Calls showq for each status: completed, running, idle and blocked.

	# TODO: Recycle previous jobs (which might contain more info)
	jobs = []

	# Completed jobs
	prog = <<-END_AWK
		/^[0-9]+/ {
			if (!match($3, /jobs?/))
			{
				print "-";
				print "  :id:", substr($1, 1, index($1, "/") - 1);
				print "  :name:", substr($1, index($1, "/") + index(substr($1, index($1, "/") + 1), "/") + 1);
				print "  :procs:", $12;
				print "  :status: :completed";
				print "  :exit:", $3;
				print "  :elapsed: \\"" $13 "\\"";
				print "  :efficacy:", $6;
				print "  :xfactor:", $7;
				print "  :stop:", $14, $15, $16, $17;
				print "  :user:", $9;
				print "  :group:", $10;
			}
		}
	END_AWK
	jobs.concat((YAML.load `showq -w user=$USER -c -n -v | awk '#{prog}'`) || [])

	# Running jobs
	prog = <<-END_AWK
		/^[0-9]+/ {
			if (!match($3, /jobs?/))
			{
				print "-";
				print "  :id:", substr($1, 1, index($1, "/") - 1);
				print "  :name:", substr($1, index($1, "/") + index(substr($1, index($1, "/") + 1), "/") + 1);
				print "  :procs:", $11;
				print "  :status: :running";
				print "  :remaining: \\"" $12 "\\"";
				print "  :efficacy:", $5;
				print "  :xfactor:", $6;
				print "  :start:", $13, $14, $15, $16;
				print "  :user:", $8;
				print "  :group:", $9;
			}
		}
	END_AWK
	jobs.concat((YAML.load `showq -w user=$USER -r -n -v | awk '#{prog}'`) || [])

	# Idle jobs
	prog = <<-END_AWK
		BEGIN {
			total = 0;
		}

		/^[0-9]+/ {
			if (!match($3, /jobs?/))
			{
				++total;
				if (match($5, /#{ENV['USER']}/))
				{
					rank = total;
					id[rank] = substr($1, 1, index($1, "/") - 1);
					name[rank] = substr($1, index($1, "/") + index(substr($1, index($1, "/") + 1), "/") + 1);
					procs[rank] = $7;
					walltime[rank] = "\\"" $8 "\\"";
					priority[rank] = $2;
					xfactor[rank] = $3;
					estimated[rank] = "\\"" $10 "\\"";
					user[rank] = $5;
					group[rank] = $6;
					class[rank] = $9;
				}
			}
		}

		END {
			for (rank in id)
			{
				print "-";
				print "  :id:", id[rank];
				print "  :name:", name[rank];
				print "  :procs:", procs[rank];
				print "  :walltime:", walltime[rank];
				print "  :status: :idle";
				print "  :priority:", priority[rank];
				print "  :xfactor:", xfactor[rank];
				print "  :rank:", rank "/" total;
				print "  :estimated:", estimated[rank];
				print "  :user:", user[rank];
				print "  :group:", group[rank];
				print "  :class:", class[rank];
			}
		}
	END_AWK
	jobs.concat((YAML.load `showq -i -n -v | awk '#{prog}'`) || [])

	# Blocked jobs
	prog = <<-END_AWK
		/^[0-9]+/ {
			if (!match($3, /jobs?/))
			{
				print "-";
				print "  :id:", substr($1, 1, index($1, "/") - 1);
				print "  :name:", substr($1, index($1, "/") + index(substr($1, index($1, "/") + 1), "/") + 1);
				print "  :procs:", $4;
				print "  :walltime: \\"" $5 "\\"";
				print "  :status: :blocked";
				print "  :queue:", $6, $7, $8, $9;
				print "  :user:", $2;
				print "  :state:", $3;
			}
		}
	END_AWK
	jobs.concat((YAML.load `showq -w user=$USER -b -n -v | awk '#{prog}'`) || [])

	jobs
end


init do
	jobs = getJobs
	selection = nil
	display(jobs, selection)

	loop do
		case Curses.getch
		when Curses::Key::UP then selection = prevJob(jobs, selection)
		when Curses::Key::DOWN then selection = nextJob(jobs, selection)
		when 10, 32, ' ', Curses::Key::RIGHT then details(jobs, selection) # 10 = enter, 32 = space
		when ?q, ?Q, 27 then break # 27 = escape
		when ?r, ?R then jobs = getJobs
		when ?h, ?H, ?? then help
		end
		display(jobs, selection)
	end
end
