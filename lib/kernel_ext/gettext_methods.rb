#coding: utf-8

def _(str)
  kas = _kas
  session = _session
  locale = nil
  
  if Thread.current[:locale].to_s.length > 0
    locale = Thread.current[:locale]
  elsif session and session[:locale].to_s.strip.length > 0
    locale = session[:locale]
  elsif kas and kas.config[:locale_default].to_s.strip.length > 0
    session[:locale] = kas.config[:locale_default] if session
    locale = kas.config[:locale_default]
  elsif !session and !kas
    return str
  else
    raise "No locale set for session and ':locale_default' not set in config."
  end
  
  return kas.gettext.trans(locale, str)
end