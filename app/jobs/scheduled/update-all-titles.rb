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

      trust_levels = [0, 1, 2, 3, 4]
      titles = {
        0 => tl0_title,
        1 => tl1_title,
        2 => tl2_title,
        3 => tl3_title,
        4 => tl4_title,
      }

      if SiteSetting.add_primary_group_title
        titles.each do |tl, title_template|
          next if title_template.blank?

          DB.exec(<<~SQL, title_template, tl)
            UPDATE users
            SET title = REPLACE(?, '{group_name}', groups.name)
            FROM groups
            WHERE users.primary_group_id = groups.id
              AND users.trust_level = ?
              AND users.primary_group_id IS NOT NULL;
          SQL
        end
      else
        titles.each do |tl, title_text|
          next if title_text.blank?

          User.where(trust_level: tl).update_all(title: title_text)
        end
      end
    end
  end
end
