# frozen_string_literal: true

module AddTitleBasedOnTrustLevel
  class UpdateTitles < ::Jobs::Scheduled
    every SiteSetting.update_title_frequency.hours # Run based on site setting

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

      titles.each do |tl, title_template|
        next if title_template.blank?

        if SiteSetting.add_primary_group_title
          # Users WITH a primary group: replace {group_name} with the group name
          DB.exec(<<~SQL, title_template, tl)
            UPDATE users
            SET title = REPLACE(?, '{group_name}', groups.name)
            FROM groups
            WHERE users.primary_group_id = groups.id
              AND users.trust_level = ?
              AND users.primary_group_id IS NOT NULL;
          SQL

          # Users WITHOUT a primary group: apply template removing the placeholder
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
  end
end
