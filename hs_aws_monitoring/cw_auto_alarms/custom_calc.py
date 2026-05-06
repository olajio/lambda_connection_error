class CustomCalc:

    @classmethod
    def percent_of_tag(cls, tags, threshold_tag_name, threshold_percent):
        return str(int(int(tags.get(threshold_tag_name)) * (threshold_percent / 100)))

    @classmethod
    def ninety_percent_of_iops(cls, tags, threshold_tag_name, threshold_percent):
        # Keeping this for reverse compatibility, this will be deprecated in favor of percent_of_tag.
        return cls.percent_of_tag(tags, threshold_tag_name, threshold_percent)
