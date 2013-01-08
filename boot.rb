env = ENV['RACK_ENV'] || 'development'

require 'bundler'
Bundler.require
require 'will_paginate/active_record'

YAML::load(File.open('config/database.yml'))[env].each do |key,value|
  set key.to_sym, value
end

ActiveRecord::Base.establish_connection(
  adapter: 'mysql2',
  host: settings.db_host,
  database: settings.db_name,
  username: settings.db_user,
  password: settings.db_password)

class Quote < ActiveRecord::Base
  self.table_name = "quote"
  self.per_page = 10
  belongs_to :user, :foreign_key => :nick_id, :counter_cache => true
  has_many :ratings, :foreign_key => :quote_id

  def current_rating
    ratings_count
  end
end

class User < ActiveRecord::Base
  self.table_name = "nick"
  has_many :quotes, :foreign_key => :nick_id
  has_many :ratings, :foreign_key => :nick_id
end

class Rating < ActiveRecord::Base
  self.table_name = "rating"
  belongs_to :user, :foreign_key => :nick_id
  belongs_to :quote, :foreign_key => :quote_id

  validates :rating, :numericality => { :only_integer => true }
  validates :rating, :inclusion => { :in => (0..10) }

  after_save do |rating|
    q = Quote.where(:id => rating.quote_id).first

    quote_ratings_count = Rating.where(:quote_id => q.id).count
    quote_ratings_total = Rating.where(:quote_id => q.id).sum(:rating)
    quote_rating = quote_ratings_total / quote_ratings_count

    q.ratings_count = quote_ratings_count
    q.rating = quote_rating
    q.save
  end
end

helpers do
  def page
    [params[:page].to_i, 1].max
  end
end

before do
  @current_user = User.find(session[:uid]) unless session[:uid].nil?
end

get '/' do
  @quotes = Quote.paginate(:page => page).order("rating DESC, ratings_count DESC")
  erb :index
end

get '/auth/:uid/:authcode' do
  session[:uid] = nil
  user = User.where(:id => params[:uid], :auth_code => params[:authcode]).first
  if user.nil?
    flash[:error] = "Sorry, there was a problem authenticating you, please try again via the enoch bot"
  else
    user.update_attributes(:auth_code => nil)
    session[:uid] = user.id
    flash[:info] = "Thanks, you've been authenticated now"
  end
  redirect '/'
end

get '/auth/logout' do
  flash[:info] = "Thanks, you've been logged out now" unless session[:uid].nil?
  session[:uid] = nil
  redirect '/'
end

get '/quote/:id' do
  @quote = Quote.where(id: params[:id]).first
  if @quote.nil?
    flash[:error] = "Sorry, that quote couldn't be found"
    redirect '/'
  else
    erb :quote_display
  end
end

get '/channels' do
  @channels = Quote.select(:channel).uniq
  erb :channel_list
end

get '/channels/:name' do
  channel = params[:name]
  @quotes = Quote.where(:channel => [channel,"##{channel}"]).paginate(:page => page).order("rating DESC, ratings_count DESC")
  if @quotes.nil? || @quotes.count == 0
    flash[:error] = "Sorry, the channel you specified can't be found"
    redirect '/channels'
  end
  erb :index
end

get '/users/:nick' do
  @quotes = Quote.where(:nick => params[:nick]).paginate(:page => page).order("rating DESC, ratings_count DESC")
  if @quotes.nil? || @quotes.count == 0
    flash[:error] = "Sorry, the nick specified can't be found"
    redirect '/'
  end
  erb :index
end

get '/unrated' do
  if @current_user.nil?
    flash[:error] = "Sorry, you need to be authenticated to view that page"
    redirect '/'
  end
  @quotes = Quote.paginate(:page => page).where("quote.nick_id <> #{@current_user.id}").all(:joins => "left join rating on (quote.id = rating.quote_id and rating.nick_id = #{@current_user.id})", :conditions => {"rating.id" => nil, :channel => @current_user.quotes.pluck(:channel).uniq})
  erb :index
end

post '/rate_quotes' do
  if @current_user.nil?
    flash[:error] = "Sorry, you need to be authenticated to rate quotes"
    if params[:return_to].nil?
      redirect '/'
    else
      redirect params[:return_to]
    end
  end
  params[:rating].each do |r|
    q = Quote.where(:id => r[0]).first
    unless q.nil? || q.nick_id == @current_user.id
      rating = Rating.where(:quote_id => q.id, :nick_id => @current_user.id).first
      if rating.nil?
        rating = Rating.create(:quote_id => q.id, :nick_id => @current_user.id, :rating => r[1])
      else
        rating.update_attributes(rating: r[1])
      end
    end
  end
  if params[:return_to].nil?
    redirect '/'
  else
    redirect params[:return_to]
  end
end
