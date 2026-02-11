# frozen_string_literal: true

module AddTitleBasedOnTrustLevel
  class UpdateTitles < ::Jobs::Scheduled
    every SiteSetting.update_title_frequency.hours # Run based on site setting

    PROGRESS_BAR_LENGTH = 10
    FILLED_CHAR = "\u2588"   # █
    EMPTY_CHAR  = "\u2591"   # ░

    # Discourse trust level requirements (default thresholds)
    TL_REQUIREMENTS = {
      1 => {
        topics_entered: :tl1_requires_topics_entered,
        read_posts: :tl1_requires_read_posts,
        time_spent_mins: :tl1_requires_time_spent_mins,
        days_visited: :tl1_requires_days_visited,
        likes_given: :tl1_requires_likes_given,
        likes_received: :tl1_requires_likes_received,
      },
      2 => {
        topics_entered: :tl2_requires_topics_entered,
        read_posts: :tl2_requires_read_posts,
        time_spent_mins: :tl2_requires_time_spent_mins,
        days_visited: :tl2_requires_days_visited,
        likes_given: :tl2_requires_likes_given,
        likes_received: :tl2_requires_likes_received,
      },
      3 => {
        days_visited: :tl3_requires_days_visited,
        topics_replied_to: :tl3_requires_topics_replied_to,
        topics_viewed: :tl3_requires_topics_viewed,
        posts_read: :tl3_requires_posts_read,
        likes_given: :tl3_requires_likes_given,
        likes_received: :tl3_requires_likes_received,
      },
    }.freeze

    def execute(args)
      tl0_title = SiteSetting.tl0_title_on_create
      tl1_title = SiteSetting.tl1_title_on_promotion
      tl2_title = SiteSetting.tl2_title_on_promotion
      tl3_title = SiteSetting.tl3_title_on_promotion
      tl4_title = SiteSetting.tl4_title_on_promotion

      titles = {
        0 => tl0_title,
        1 => tl1_title,
        2 => tl2_title,
        3 => tl3_title,
        4 => tl4_title,
      }

      show_progress = SiteSetting.show_progress_bar_in_title

      if show_progress
        # Per-user update with individual progress bar
        update_titles_with_progress(titles)
      else
        # Bulk update without progress bar
        update_titles_bulk(titles)
      end
    end

    private

    def update_titles_bulk(titles)
      titles.each do |tl, title_template|
        next if title_template.blank?

        if SiteSetting.add_primary_group_title
          DB.exec(<<~SQL, title_template, tl)
            UPDATE users
            SET title = REPLACE(?, '{group_name}', groups.name)
            FROM groups
            WHERE users.primary_group_id = groups.id
              AND users.trust_level = ?
              AND users.primary_group_id IS NOT NULL;
          SQL

          DB.exec(<<~SQL, title_template.gsub('{group_name}', ''), tl)
            UPDATE users
            SET title = ?
            WHERE users.trust_level = ?
              AND (users.primary_group_id IS NULL);
          SQL
        else
          User.where(trust_level: tl).update_all(title: title_template)
        end
      end
    end

    def update_titles_with_progress(titles)
      titles.each do |tl, title_template|
        next if title_template.blank?

        User.where(trust_level: tl).find_each do |user|
          base_title = resolve_title(title_template, user)
          progress_bar = build_progress_bar(user, tl)
          final_title = progress_bar ? "#{base_title} #{progress_bar}" : base_title

          user.update_columns(title: final_title) if user.title != final_title
        end
      end
    end

    def resolve_title(template, user)
      if SiteSetting.add_primary_group_title && user.primary_group_id.present?
        group = Group.find_by(id: user.primary_group_id)
        template.gsub('{group_name}', group&.name.to_s)
      else
        template.gsub('{group_name}', '')
      end
    end

    def build_progress_bar(user, current_tl)
      next_tl = current_tl + 1
      return nil if next_tl > 4
      return nil unless TL_REQUIREMENTS.key?(next_tl)

      requirements = TL_REQUIREMENTS[next_tl]
      return nil if requirements.blank?

      percentages = []

      requirements.each do |stat_key, setting_key|
        required = SiteSetting.public_send(setting_key).to_f
        next if required <= 0

        current = user_stat_value(user, stat_key, next_tl)
        pct = [(current / required), 1.0].min
        percentages << pct
      end

      return nil if percentages.empty?

      avg = percentages.sum / percentages.size
      filled = (avg * PROGRESS_BAR_LENGTH).round
      empty = PROGRESS_BAR_LENGTH - filled
      pct_display = (avg * 100).round

      "[#{FILLED_CHAR * filled}#{EMPTY_CHAR * empty}] #{pct_display}%"
    end

    def user_stat_value(user, stat_key, next_tl)
      stat = user.user_stat
      return 0.0 unless stat

      case stat_key
      when :topics_entered
        stat.topics_entered.to_f
      when :read_posts, :posts_read
        stat.posts_read_count.to_f
      when :time_spent_mins
        stat.time_read.to_f / 60.0
      when :days_visited
        stat.days_visited.to_f
      when :likes_given
        stat.likes_given.to_f
      when :likes_received
        stat.likes_received.to_f
      when :topics_replied_to
        stat.topics_entered.to_f # approximation if no direct column
      when :topics_viewed
        stat.topics_entered.to_f
      else
        0.0
      end
    end
  end
end
