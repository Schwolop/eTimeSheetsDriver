#!/usr/bin/env ruby
#
# Automatically fills out eTimeSheets using the selenium-client API, 
# given a CSV file specifying dates, project codes, and times.
# This application is structured as test case to ease handling of errors.
#
require "test/unit"
require "rubygems"
gem "selenium-webdriver"
require "selenium-webdriver"
require 'date'

class ETimeSheetsAutoFill < Test::Unit::TestCase
    attr_reader :driver, :root_url

    def setup
        @debug = false; @require_user_input = true;
        @root_url = ENV['ETIMESHEETS_URL']
        unless @debug
            # Run the selenium server.
            @selenium_pid = Process.spawn('java -jar selenium-server-standalone-2.33.0.jar')
            @driver = Selenium::WebDriver.for :firefox
        end
    end

    def teardown
        unless @debug
            Process.kill(9,@selenium_pid) # Kill selenium.
        end
    end

    def test_autofill_timesheet
        # Database into which lines are read.
        # Format is eow->job%%%activity->date = [hours,comment]
        db = Hash.new{|h,k| h[k]=Hash.new{|h,k| h[k]=Hash.new{|h,k| h[k]=[0,""]}}}

        # Perhaps not every time, but it might be worth scraping the page to 
        # find the codes ahead of time, and checking the input file conforms
        # rather than just trying to enter whatever the user provided.

        print "\nReading data...\n"
        data = File.open('data.csv').read
        data.each_line do |line|
            unless line[0] == '#' || line == "\n" || line.empty? # Ignore comments and blank lines
                parts = line.split(',')
                date = Date::strptime(parts[0], "%d/%m/%y") # Parse as a date.

                # Determine date of end of week (sunday) for this date.
                eow_date = date
                while eow_date.sunday? == false
                    eow_date+=1 # increment until it becomes a sunday
                end
                
                commentCount = 0; tupleCount = 0; comment = nil
                while true
                    c = tupleCount*3 + commentCount # end index of previous part
                    job = parts[c+1].strip # Job code
                    activity = parts[c+2].strip # Activity code
                    hours = parts[c+3].to_f # Hours

                    # Look for optional string in the fourth part
                    if parts.length > c+4 and (parts[c+4].strip)[0]=="\"" # If it's a comment...
                        #TODO: Look for comma before closing quotation mark, and collapse next part into this one. Maybe do this in a pre-filter.
                        comment = parts[c+4].strip
                        commentCount+=1
                    end

                    # Describe output and enter into DB.
                    puts "#{date}, #{job}, #{activity}, #{hours}hrs, EOW: #{eow_date}#{comment and !comment.empty? ? ", #{comment}" : ""}"
                    db[eow_date][[job,activity].join('%%%')][date][0] += hours
                    if comment and !comment.empty?
                        unless db[eow_date][[job,activity].join('%%%')][date][1].empty? # Join additional comments on the same item/activity with a comma.
                            db[eow_date][[job,activity].join('%%%')][date][1] += ", "
                        end
                        db[eow_date][[job,activity].join('%%%')][date][1] += comment
                    end

                    tupleCount+=1

                    # Break if we've run out of parts
                    if tupleCount*3 + commentCount + 1 == parts.length
                        break
                    end
                end
            end
        end
        print "[OK]\n"

        if @require_user_input and !@debug
            puts "Press enter to fill in timesheets (type anything else and hit enter to quit)"
            exit unless gets.length <= 1
        end

        unless @debug
            # Login to eTimeSheets
            assert !root_url.nil? && !root_url.empty?, "eTimeSheets root URL not found in ENV."
            assert !ENV['ETIMESHEETS_USER'].nil? && !ENV['ETIMESHEETS_USER'].empty?, "eTimeSheets user not found in ENV."
            assert !ENV['ETIMESHEETS_PW'].nil? && !ENV['ETIMESHEETS_PW'].empty?, "eTimeSheets password not found in ENV."

            driver.navigate.to "#{@root_url}Login.asp"
            assert_equal "Greentree eTimeSheets", driver.title
            element = driver[:name => 'CoyOrg']
            element.send_keys ENV['ETIMESHEETS_USER']
            element = driver[:name => 'Password']
            element.send_keys ENV['ETIMESHEETS_PW']
            element.submit

            # Wait until page loads appear
            wait = Selenium::WebDriver::Wait.new(:timeout => 5) # seconds
            wait.until {driver.find_element(:id => "Table8") }

            # Check user logged in OK.
            assert driver.page_source.include?("LOGGED IN:"), "Failed to login user."
            
            # For each end of week in the database, submit a timesheet:
            db.each do |eow,db2|

                # Jump directly to 'Add Timesheet'
                driver.navigate.to "#{root_url}AddMyTimeSheet.asp"

                # Set the 'week ending date'
                element = driver[:id => 'WeekendDate']
                element.clear
                element.send_keys eow.strftime("%d/%m/%y")

                # Click 'Save Timesheet'
                element = driver[:id => 'Submit']
                element.submit

                # Catch error if this timesheet has already been submitted.
                assert !driver.page_source.include?("Error Detail"), "Failed to save timesheet. It is likely a timesheet for this week has already been submitted."

                # For each job/activity within this eow, add a line:
                db2.each do |job_activity,db3|
                    job=job_activity.split('%%%')[0]
                    activity=job_activity.split('%%%')[1]

                    # Click 'Add Line'
                    element = driver.find_element(:xpath, "//html/body/etimesheets/designed/form/table/tbody/tr[3]/td/table/tbody/tr[6]/td/img")
                    element.click
                    
                    # Wait until page loads
                    wait = Selenium::WebDriver::Wait.new(:timeout => 5) # seconds
                    wait.until {driver.find_element(:id => "Table4") }
                    assert driver.page_source.include?("Adding new Line Item"), "Failed to click 'Add Line'."

                    # Set 'Job Code'
                    element = driver[:id => 'JCJobCode']
                    element.clear
                    element.send_keys job
                    element.send_keys :tab
                    sleep(0.1) # Wait for 100ms
     
                    # Set 'Activity Code'
                    element = driver[:id => 'JCActivityCode']
                    element.clear
                    element.send_keys activity
                    element.send_keys :tab
                    sleep(0.1) # Wait for 100ms

                    # For each date for this job/activity, fill in hours
                    (1..7).each do |i|
                        date = eow-7+i # i=1 -> mon, i=2 -> tues, etc.
                        element = driver[:id => "Qty#{i}"]
                        if db3.has_key?(date)
                            hours = db3[date][0]
                            element.send_keys :end
                            (0..4).each {|i| element.send_keys :backspace }
                            element.send_keys hours
                        end
                        element = driver[:id => "Notes#{i}"]
                        if db3.has_key?(date)
                            comment = db3[date][1].delete("\"") # strip quotation marks.
                            element.send_keys :end
                            (0..1).each {|i| element.send_keys :backspace }
                            element.send_keys comment
                        end
                    end

                    # Click 'Save Line'
                    element = driver[:id => "Button3"]
                    element.submit
                end # each job/activity

                if @require_user_input
                    puts "Press enter to submit timesheets (type anything else and hit enter to quit)"
                    exit unless gets.length <= 1
                end

                # Click 'Submit Timesheet'
                element = driver.find_element(:xpath, "//html/body/etimesheets/designed/form/table/tbody/tr[3]/td/table/tbody/tr[10]/td/img")
                element.click

                # Wait until page loads appear
                wait = Selenium::WebDriver::Wait.new(:timeout => 5) # seconds
                wait.until {driver.find_element(:id => "Table9") }

                # Click confirm
                element = driver[:id => "Submit"]
                element.submit

            end # each end_of_week
        end # unless @debug

    end # end of test_autofill_timesheet

end # end of class