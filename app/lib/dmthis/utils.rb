# encoding: UTF-8

def format_message_from_status(status)
  # make sure we don't trunc the sender
  # or urls (any token with a / will suffice for now)
  from_text = "@#{status.user.screen_name} "
  text = shorten_but_urls(status.text, 140 - from_text.length)

  return "#{from_text}#{text}"
end

def shorten_but_urls(text, length_available)
  if text.length > length_available
    tokenized_text = text.split
    shortenable_tokens = tokenized_text.collect do |val|
      next val unless val.include? '/'
    end
    ellip = '...'
    to_shorten = text.length + ellip.length - length_available
    shortened = false
    shortenable_tokens.reverse!.collect! do |val|
      next if val == nil
      if to_shorten > 0
        val_length = val.length
        shorten_by = [val_length, to_shorten].min
        val = val.slice(0, val_length-shorten_by)
        to_shorten -= shorten_by + 1
        if !shortened && val_length != shorten_by
          shortened = true
          next "#{val}#{ellip}"
        else
          next val
        end
      end
    end
    shortenable_tokens.reverse!

    return tokenized_text.collect.with_index { |val, i|
      val = shortenable_tokens[i] if shortenable_tokens[i] != nil
      if !shortened && shortenable_tokens.length-1 > i &&
                       shortenable_tokens[i+1].empty?
        shortened = true
        val << ellip
      end
      val
    }.reject(&:empty?).join(' ').sub(" #{ellip}", ellip).strip
  else
    text.strip
  end
end

