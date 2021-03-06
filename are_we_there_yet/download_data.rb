# This script should be executed calling $ bundle exec ruby download_data.rb

require "bundler"

require "psych"
require "google/api_client"
require "google_drive"
require "colorize"
require "faraday" # HTTP requests library
require "set"

puts "Start of script".green

use_oauth = true

if use_oauth then
  session = GoogleDrive.saved_session("oauth_config.json")
else
  if not (ENV['google_mail'] and ENV['google_password']) then
	raise "Environment variables 'google_mail' and 'google_password' need to be set."
  end
  session = GoogleDrive.login( ENV['google_mail'], ENV['google_password'])
end

if not session then
  raise "Failed to open GoogleDrive session"
else
  puts "Started google session", session
end

spreadsheet_key = "0AqLzqcYZJN2cdEhBMlFpUzU2OTZHUXNoWW1aNlJvOUE"
spreadsheet = session.spreadsheet_by_key(spreadsheet_key)

if spreadsheet.nil?
  raise "Failed to obtain the requested spreadsheet"
else
  puts "Obtained spreadsheet with worksheets:", spreadsheet.worksheets
end

data_worksheet = spreadsheet.worksheets[1]
datasets_worksheet = spreadsheet.worksheets[2]

if data_worksheet.title != "Curated data" then
	raise "Got the wrong data worksheet (named #{data_worksheet.title})" 
end

if datasets_worksheet.title != "Datasets" then
	raise "Got the wrong datasets worksheet (named #{datasets_worksheet.title})" 
end

puts "Found spreadsheet data, processing..."


def check_url url

  ret = true # return value
  if url == nil then
    ret = true
  elsif url.start_with? "http" then
    begin
      http_status = Faraday.head(url).status
    rescue Exception => e
     #puts "Something when terribly wrong when consulting url ".red + url.yellow + "( " + e.to_s.light_red + " )"
     #http_status = "??"
     http_status = "ERROR ?? " + e.to_s
    end

    if http_status == 200 then
      puts "Found " + url.light_blue
      ret = true
    else
      puts "Indicated url does not exists ".red + url.yellow + " HTTP status ".red + http_status.to_s.red
      ret = false
    end
  else 
    file_path = File.join "source/images/", url
    if File.exists? file_path then
       puts "Found " + file_path.light_blue
      ret = true
    else
     puts "Indicated image file does not exists ".red + url.yellow + " " + file_path.light_yellow
     ret = false
    end
  end

  ret
end # end of check_url


def check_dataset_urls dataset

  check_url dataset[:figure_url]
  check_url dataset[:external_results_url]

end # end of check_dataset_urls


def read_datasets_data worksheet

	rows = worksheet.rows

	# we assume data is the right one,
	# we skip first row (with the names)
	data = rows[1..-1].map do |row|
		{ group: row[0],
		  name: row[1],
		  evaluation_units: row[2],
		  description: row[3],
		  figure_url: row[4],
		  external_results_url: row[5]
		} if not row[0].empty?
	end

	# remove nil entries (from row.empty? == true), and empty strings
	data = data.compact 
	data = data.map { |datum| datum.select {|k,v| v and not v.empty?} }
	
	data.map { |d| check_dataset_urls d }
        
	groups = Set.new
	data.each {|x| groups.add x[:group] }
	grouped_datasets = {}
	groups.each do |g|
	 grouped_datasets[g] = data.select { |x| x[:group] == g }
	end

	grouped_datasets
end # end of read_datasets_data


def read_curated_data worksheet

	rows = worksheet.rows

	# we assume data is the right one,
	# we skip first row (with the names)
	data = rows[1..-1].map do |row|
		{ #timestamp: row[0],
		  dataset_name: row[1],
		  paper_name: row[2].delete("\n"),
		  paper_year: row[3],
		  paper_venue: row[4],
		  result: row[5],
		  paper_pdf_url: row[6].strip,
		  additional_information: row[7]
		} if not row[0].empty?
	end

	# remove nil entries (from row.empty? == true), and empty strings
	data = data.compact 
	data = data.map{ |datum| datum.select {|k,v| v and not v.empty?} }
	
	# FIXME this should be a command line option
	#check_all_urls = false
	check_all_urls = true
	if check_all_urls
	  data.map { |datum| check_url datum[:paper_pdf_url] }
	end
	
	data
end # end of read_curated_data


def save_data data, path

	out_file = File.open(path, "w")
	Psych.dump(data, out_file)
	out_file.close()

	puts "Updated data file #{path}"
end # end of save_data

datasets_data = read_datasets_data datasets_worksheet
curated_data = read_curated_data data_worksheet

save_data datasets_data, "data/datasets.yml"
save_data curated_data, "data/curated_data.yml"

puts "End of game. Have a nice day !".green

