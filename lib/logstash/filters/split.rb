# encoding: utf-8
require "logstash/filters/base"
require "logstash/namespace"

# The split filter clones an event by splitting one of its fields and
# placing each value resulting from the split into a clone of the original
# event. The field being split can either be a string or an array.
#
# An example use case of this filter is for taking output from the
# <<plugins-inputs-exec,exec input plugin>> which emits one event for
# the whole output of a command and splitting that output by newline -
# making each line an event.
#
# The end result of each split is a complete copy of the event
# with only the current split section of the given field changed.
class LogStash::Filters::Split < LogStash::Filters::Base

  config_name "split"

  # The string to split on. This is usually a line terminator, but can be any
  # string.
  config :terminator, :validate => :string, :default => "\n"

  # The field whose value is to be split by the terminator.
  config :field, :validate => :string, :default => "message"

  # The field within the new event which the value is split into.
  # If not set, the target field defaults to split field name.
  config :target, :validate => :string

  # If new event is a hash, merge it with the root object or target if specified.
  config :merge_hash, :validate => :boolean, :default => false

  # Delete source field after successful split unless target is the same.
  config :delete_field, :validate => :boolean, :default => false

  public
  def register
    # Nothing to do
  end # def register

  private
  def can_merge_root?(value)
    # Merge root with hash if target field haven't been specified.
    value.is_a? Hash and @target.nil?
  end

  private
  def can_merge_target?(value)
    # Merge target with hash if target isn't source.
    value.is_a? Hash and @target and @target != @field
  end

  private
  def can_delete_field?
    # Delete source field as long as we aren't merging into the same field.
    # We do allow an unspecified target since it will merge to root by default.
    return true if @merge_hash and @target != @field

    # Delete field as long as we aren't splitting into the same field.
    return true if (@target || @field) != @field

    # Field isn't in-use, it's ok to delete.
    return false
  end

  public
  def filter(event)

    original_value = event[@field]

    if original_value.is_a?(Array)
      splits = original_value
    elsif original_value.is_a?(String)
      # Using -1 for 'limit' on String#split makes ruby not drop trailing empty
      # splits.
      splits = original_value.split(@terminator, -1)
    else
      raise LogStash::ConfigurationError, "Only String and Array types are splittable. field:#{@field} is of type = #{original_value.class}"
    end

    # Skip filtering if splitting this event resulted in only one thing found.
    return if splits.length == 1 && original_value.is_a?(String)
    #or splits[1].empty?

    splits.each do |value|
      next if value.empty?

      event_split = event.clone
      @logger.debug("Split event", :value => value, :field => @field)

      output_field = (@target || @field)

      if @merge_hash and can_merge_root? value
        event_split.append(value)
      else
        if @merge_hash and can_merge_target? value
          value = event_split.get(output_field).merge(value)
        end
        event_split.set(output_field, value)
      end

      if @delete_field and can_delete_field?
        event_split.remove(@field)
      end

      filter_matched(event_split)

      # Push this new event onto the stack at the LogStash::FilterWorker
      yield event_split
    end

    # Cancel this event, we'll use the newly generated ones above.
    event.cancel
  end # def filter
end # class LogStash::Filters::Split
