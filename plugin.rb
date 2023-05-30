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