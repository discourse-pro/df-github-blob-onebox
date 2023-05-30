# name: df-github-blob-onebox
# about: The plugin removes the limitation for the maximum number of code lines of the standard GitHub Blob Onebox.
# version: 3.0.0
# authors: Dmitry Fedyuk
# url: https://discourse.pro
Rake::Task.define_task 'df:refresh_oneboxes', [:delay] => :environment do |_, args|
	require 'post'
	require 'rake/task'
	require 'site_setting_extension'
	args.with_defaults(delay: 5)
	delay = args[:delay]&.to_i
	puts "Rebaking post markdown for '#{RailsMultisite::ConnectionManagement.current_db}'"
	disable_edit_notifications = SiteSetting.disable_edit_notifications
	SiteSetting.disable_edit_notifications = true
	total = Post.count
	count = 0
	Post.find_each do |post|
		count += 1
		post.df_delay_for = (delay * count).seconds
		post.rebake!(invalidate_oneboxes: true)
		print "\r%9d / %d (%5.1f%%)" % [count, total, ((count.to_f / total.to_f) * 100).round(1)]
	end
	SiteSetting.disable_edit_notifications = disable_edit_notifications
	puts "", "#{count} posts done!", "-" * 50
end
after_initialize do
	require 'post'
	Post.module_eval do
		attr_accessor :df_delay_for
		# Enqueue post processing for this post
		def trigger_post_process(bypass_bump = false)
			args = {
				post_id: id,
				bypass_bump: bypass_bump
			}
			args[:image_sizes] = image_sizes if image_sizes.present?
			args[:invalidate_oneboxes] = true if invalidate_oneboxes.present?
			args[:cooking_options] = self.cooking_options
			# 2018-01-23
			if @df_delay_for
				args[:delay_for] = @df_delay_for								
			end
			#args[:delay_for] = 5.seconds
			Jobs.enqueue(:process_post, args)
			DiscourseEvent.trigger(:after_trigger_post_process, self)
		end
  end
end
# 2023-05-30
require './lib/onebox/layout_support'
require './lib/onebox/engine/github_blob_onebox'
require './lib/onebox/mixins/git_blob_onebox'
class Onebox::Engine::GithubBlobOnebox
  include Onebox::Mixins::GitBlobOnebox
  # 2018-01-22
  alias_method :core__initialize, :initialize
  def initialize(link, timeout = nil)
    core__initialize link, 3600
  end
  # 2016-10-04
  # An example of overriding the standard onebox engine: https://github.com/discourse/discourse/blob/v2.0.0/plugins/lazyYT
  # A forum post with an explanation: https://meta.discourse.org/t/42321
  # 2022-08-14 https://github.com/discourse/discourse/blob/v2.9.0.beta9/plugins/lazy-yt/plugin.rb#L11
  private
  @selected_lines_array  = nil
  @selected_one_liner = 0
  def calc_range(m,contents_lines_size)
    truncated = false
    from = /\d+/.match(m[:from])             #get numeric should only match a positive interger
    to   = /\d+/.match(m[:to])               #get numeric should only match a positive interger
    range_provided = !(from.nil? && to.nil?) #true if "from" or "to" provided in URL
    from = from.nil? ?  1 : from[0].to_i     #if from not provided default to 1st line
    to   = to.nil?   ? -1 : to[0].to_i       #if to not provided default to undefiend to be handled later in the logic

    if to === -1 && range_provided   #case "from" exists but no valid "to". aka ONE_LINER
      one_liner = true
      to = from
    else
      one_liner = false
    end

    unless range_provided  #case no range provided default to 1..MAX_LINES
      from = 1
      to   = MAX_LINES
      truncated = true if contents_lines_size > MAX_LINES
      #we can technically return here
    end

    from, to = [from,to].sort                                #enforce valid range.  [from < to]
    from = 1 if from > contents_lines_size                   #if "from" out of TOP bound set to 1st line
    to   = contents_lines_size if to > contents_lines_size   #if "to" is out of TOP bound set to last line.

    if one_liner
      @selected_one_liner = from
      if EXPAND_ONE_LINER != EXPAND_NONE
        if (EXPAND_ONE_LINER & EXPAND_BEFORE != 0) # check if EXPAND_BEFORE flag is on
          from = [1, from - LINES_BEFORE].max      # make sure expand before does not go out of bound
        end

        if (EXPAND_ONE_LINER & EXPAND_AFTER != 0)          # check if EXPAND_FLAG flag is on
          to = [to + LINES_AFTER, contents_lines_size].min # make sure expand after does not go out of bound
        end

        from = contents_lines_size if from > contents_lines_size   #if "from" is out of the content top bound
        # to   = contents_lines_size if to > contents_lines_size   #if "to" is out of  the content top bound
      else
        #no expand show the one liner solely
      end
    end

# 2016-10-04
=begin
  if to-from > MAX_LINES && !one_liner  #if exceed the MAX_LINES limit correct unless range was produced by one_liner which it expand setting will allow exceeding the line limit
    truncated = true
   to = from + MAX_LINES-1
  end
=end

    {:from               => from,                 #calculated from
     :from_minus_one    => from-1,                #used for getting currect ol>li numbering with css used in template
     :to                 => to,                   #calculated to
     :one_liner          => one_liner,            #boolean if a one-liner
     :selected_one_liner => @selected_one_liner,  #if a one liner is provided we create a reference for it.
     :range_provided     => range_provided,       #boolean if range provided
     :truncated          => truncated}
  end

  def raw
    return @raw if defined?(@raw)

    m = @url.match(/github\.com\/(?<user>[^\/]+)\/(?<repo>[^\/]+)\/blob\/(?<sha1>[^\/]+)\/(?<file>[^#]+)(#(L(?<from>[^-]*)(-L(?<to>.*))?))?/mi)

    if m
      from = /\d+/.match(m[:from])   #get numeric should only match a positive interger
      to   = /\d+/.match(m[:to])     #get numeric should only match a positive interger

      @file = m[:file]
      @lang = Onebox::FileTypeFinder.from_file_name(m[:file])
      # 2018-01-23
      # 1) https://developer.github.com/changes/2014-04-25-user-content-security
      # 2) «`raw.github.com` does not redirect to `raw.githubusercontent.com` for me»:
      # https://github.com/processing/processing-docs/issues/532
      # 3) «No traffic limits or throttling»
      # https://rawgit.com
      # https://github.com/rgrove/rawgit
      cdnRawGit = 'cdn.rawgit.com'
      cdnGitHub = 'raw.githubusercontent.com'
      io = open("https://#{cdnGitHub}/#{m[:user]}/#{m[:repo]}/#{m[:sha1]}/#{m[:file]}", read_timeout: timeout)
      contents = io.read
      # 2018-01-24 https://stackoverflow.com/a/4795782
      io.close

      contents_lines = contents.lines           #get contents lines
      contents_lines_size = contents_lines.size #get number of lines

      cr = calc_range(m, contents_lines_size)    #calculate the range of lines for output
      selected_one_liner = cr[:selected_one_liner] #if url is a one-liner calc_range will return it
      from           = cr[:from]
      to             = cr[:to]
      @truncated     = cr[:truncated]
      range_provided = cr[:range_provided]
      @cr_results = cr

      if range_provided       #if a range provided (single line or more)
        if SHOW_LINE_NUMBER
          lines_result = line_number_helper(contents_lines[(from - 1)..(to - 1)], from, selected_one_liner)  #print code with prefix line numbers in case range provided
          contents = lines_result[:output]
          @selected_lines_array = lines_result[:array]
        else
          contents = contents_lines[(from - 1)..(to - 1)].join()
        end
      else
        contents = contents_lines[(from - 1)..(to - 1)].join()
      end

      if contents.length > MAX_CHARS    #truncate content chars to limits
        contents = contents[0..MAX_CHARS]
        @truncated = true
      end
      @raw = contents
    end
  end
end