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
        @root_url = ENV['ETIMESHEETS_URL']
        # Run the selenium server.
        @selenium_pid = Process.spawn('java -jar selenium-server-standalone-2.33.0.jar')
        @driver = Selenium::WebDriver.for :firefox
        @debug = true
    end

    def teardown
        Process.kill(9,@selenium_pid) # Kill selenium.
    end

    def test_autofill_timesheet
        # Database into which lines are read.
        # Format is eow->job%%%activity->date = hours
        db = Hash.new{|h,k| h[k]=Hash.new{|h,k| h[k]=Hash.new{|h,k| h[k]=0}}}

        # Perhaps not every time, but it might be worth scraping the page to 
        # find the codes ahead of time, and checking the input file conforms
        # rather than just trying to enter whatever the user provided.

        print "\nReading data..."
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
                
                numTriplets = ((parts.length-1) / 3).to_i
                assert (parts.length-1)%3==0, "Input contains a line with a number of parts that isn't one greater than a multiple of three. Format should be date, job code, activity code, hours, (job code, activity code, hours), where there may be multiple triplets after the first."
                (0..numTriplets-1).each do |t|
                    job = parts[t*3 + 1].strip # Job code
                    activity = parts[t*3 + 2].strip # Activity code
                    hours = parts[t*3 + 3].to_f # Hours
                    puts "#{date}, #{job}, #{activity}, #{hours}hrs, EOW: #{eow_date}"
                    db[eow_date][[job,activity].join('%%%')][date] += hours
                end
            end
        end
        print "[OK]\n"

        if @debug
            puts "Press enter to fill in timesheets (type anything else and hit enter to quit)"
            exit unless gets.length <= 1
        end

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
            # TODO: Catch any error about timesheet already submitted!

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
 
                # Set 'Activity Code'
                element = driver[:id => 'JCActivityCode']
                element.clear
                element.send_keys activity
                element.send_keys :tab

                #TODO Typing in hours isn't working. It fails to clear the 0.00 already there.

                # For each date for this job/activity, fill in hours
                (1..7).each do |i|
                    date = eow-7+i # i=1 -> mon, i=2 -> tues, etc.
                    element = driver[:id => "Qty#{i}"]
                    if db3.has_key?(date)
                        hours = db3[date]
                        element.send_keys :end
                        (0..4).each {|i| element.send_keys :backspace }
                        element.send_keys hours
                    end
                end

                # Click 'Save Line'
                element = driver[:id => "Button3"]
                element.submit
            end # each job/activity

            if @debug
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

    end # end of test_autofill_timesheet

end # end of class