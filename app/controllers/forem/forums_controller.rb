require 'forum_common'
module Forem
  class ForumsController < Forem::ApplicationController
    load_and_authorize_resource :class => 'Forem::Forum', :only => :show
    before_filter :authenticate_user!
    before_action :set_page_title

    helper 'forem/topics'
    include ForumCommon

    def index
      @categories = Forem::Category.order('position DESC')
    end

    def show
      redirect_to main_app.private_path('coffee-shop') and return if params[:key] && params[:key] == 'private'

      MixpanelDelay.new.track_app_event(
        'id' => current_user.id,
        'type' => 'View Coffee Shop',
        'properties' => {
      })
      authorize! :show, @forum
      register_view
      @sort = params[:sort]
      @search = params[:search] ? params[:search].downcase : params[:search]
      @is_public_search = false
      @subscribed_topics_ids = Forem::Subscription.where(subscriber_id: current_user).pluck(:topic_id)

      if can? :create_topic, @forum
        @topic = @forum.topics.build
        @topic.posts.build
        @new_id = DateTime.now.strftime('%Q')
      end

      if @sort == 'search'
        if params[:tag].present?
          @tag = Forem::Tag.find_by_tag(params[:tag])
          @collection = Forem::Topic.joins(:topic_tags)
                        .where('forem_topic_tags.tag_id = ?', @tag.id)
                        .by_most_recent_post
        else
          matched_users_ids = User.where('user_name LIKE ?', "%#{@search}%").pluck(:id)

          @collection = Forem::Topic.uniq
                        .joins('LEFT OUTER JOIN forem_topic_tags ON forem_topic_tags.topic_id = forem_topics.id')
                        .joins('LEFT OUTER JOIN forem_tags ON forem_topic_tags.tag_id = forem_tags.id')
                        .where('lower(forem_tags.tag) LIKE ? OR lower(subject) LIKE ? OR user_id IN (?)', "%#{@search}%", "%#{@search}%", matched_users_ids)
                        .by_most_recent_post

        end
        @collection = @collection.send(pagination_method, params[pagination_param]).per(Forem.per_page)
        @is_public_search = true
      else
        tags = Forem::Tag.where(hidden: true).pluck(:id)
        if tags.present?
          @collection = Forem::Topic.where('forem_topics.id NOT IN (?)',
                                           Forem::TopicTag.select(:topic_id)
                                           .where('forem_topic_tags.tag_id IN (?)', tags) )
                        .by_most_recent_post
        else
          @collection = Forem::Topic.by_most_recent_post
        end
      end
      @collection = @collection.includes(last_post: [:forem_user])
      @collection = @collection.send(pagination_method, params[pagination_param]).per(Forem.per_page)

      respond_to do |format|
        format.html
        format.atom { render :layout => false }
        format.js
      end
    end

    def sort
      redirect_to forem.forum_topics_path('coffee-shop', sort_by: params[:sort_by])
    end

    def sort_by
      @forum = Forem::Forum.first
      @sort = params[:sort]
      tags = Forem::Tag.where(hidden: true).pluck(:id)
      #if tag selected
      if params[:tag].present?
        @tag = Forem::Tag.find(params[:tag])
        if @sort == 'popular'
          @collection = Forem::Topic.joins(:topic_tags)
          .select('*, forem_topics.id, (SELECT SUM(s) FROM UNNEST(forem_topics.views_table) s) as views_sum')
          .where('forem_topic_tags.tag_id = ?', @tag.id)
          .order('views_sum DESC')
          
        elsif @sort == 'following'
          @collection = Forem::Topic.joins(:topic_tags)
          .where('forem_topic_tags.tag_id = ?', @tag.id)
          .where(id: Forem::Subscription.where(subscriber_id: current_user).pluck(:topic_id))
          .by_most_recent_post
          
        else
          @collection = Forem::Topic.joins(:topic_tags)
          .where('forem_topic_tags.tag_id = ?', @tag.id)
          .by_most_recent_post
          
        end
      #no tag selected  
      else
        if @sort == 'popular'
          if tags.present?
            @collection = Forem::Topic.select('*, (SELECT SUM(s) FROM UNNEST(views_table) s) as views_sum')
                          .where('forem_topics.id NOT IN (?)',
                            Forem::TopicTag.select(:topic_id)
                            .where('forem_topic_tags.tag_id IN (?)', tags) )
                          .order('views_sum DESC')
          else
            @collection = Forem::Topic.select('*, (SELECT SUM(s) FROM UNNEST(views_table) s) as views_sum')
                          .order('views_sum DESC')
          end
        elsif @sort == 'following'
          @collection = Forem::Topic.where(id: Forem::Subscription.where(subscriber_id: current_user).pluck(:topic_id))
                        .by_most_recent_post
        else
          if tags.present?
            @collection = Forem::Topic
                          .where('forem_topics.id NOT IN (?)',
                            Forem::TopicTag.select(:topic_id)
                            .where('forem_topic_tags.tag_id IN (?)', tags) )
                          .by_most_recent_post
          else
            @collection = Forem::Topic.where('TRUE = TRUE').by_most_recent_post
          end
        end
      end
      @collection = @collection.send(pagination_method, params[pagination_param]).per(Forem.per_page)
    end

    private
    def register_view
      @forum.register_view_by(forem_user)
    end

    def set_page_title
      @page_title = 'Coffee shop | Rosemary Conley'
    end
  end
end