#coding: utf-8

def _(str)
  hb = _hb
  session = Thread.current[:hayabusa][:session].sess_data if Thread.current[:hayabusa] and Thread.current[:hayabusa][:session]
  locale = nil
  
  if Thread.current[:locale].to_s.length > 0
    locale = Thread.current[:locale]
  elsif session and session[:locale].to_s.strip.length > 0
    locale = session[:locale]
  elsif hb and hb.config[:locale_default].to_s.strip.length > 0
    session[:locale] = hb.config[:locale_default] if session
    locale = hb.config[:locale_default]
  elsif !session and !hb
    return str
  else
    raise "No locale set for session and ':locale_default' not set in config."
  end
  
  return hb.gettext.trans(locale, str)
end