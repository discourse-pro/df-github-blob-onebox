# name: df-github-blob-onebox
# about: The plugin removes the limitation for the maximum number of code lines of the standard GitHub Blob Onebox.
# version: 1.0.0
# authors: Dmitry Fedyuk
# url: https://discourse.pro

# 2016-10-04
# Пример перекрытия onebox: https://github.com/discourse/discourse/tree/master/plugins/lazyYT
# Пояснения здесь: https://meta.discourse.org/t/12486/4
class Onebox::Engine::GithubBlobOnebox

  private
  @selected_lines_array  = nil
  @selected_one_liner = 0
  def calc_range(m,contents_lines_size)
    #author Lidlanca  09/15/2014
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

end

