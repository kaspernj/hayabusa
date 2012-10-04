#coding: utf-8

def _(str)
  thread = Thread.current
  thread_hayabusa = thread[:hayabusa]
  raise "Could not register Hayabusa-data." if !thread_hayabusa
  hb = thread_hayabusa[:hb]
  raise "Could not register Hayabusa." if !hb
  raise "'gettext' not enabled for Hayabusa." if !hb.gettext
  
  session = thread_hayabusa[:session].sess_data if thread_hayabusa[:session]
  locale = nil
  
  if !thread[:locale].to_s.empty?
    locale = thread[:locale]
  elsif session and !session[:locale].to_s.strip.empty?
    locale = session[:locale]
  elsif hb and !hb.config[:locale_default].to_s.strip.empty?
    session[:locale] = hb.config[:locale_default] if session
    locale = hb.config[:locale_default]
  elsif !session and !hb
    return str
  else
    raise "No locale set for session and ':locale_default' not set in config."
  end
  
  return hb.gettext.trans(locale, str)
end