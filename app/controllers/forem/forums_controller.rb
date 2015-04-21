require 'forum_common'
module Forem
  class ForumsController < Forem::ApplicationController
    load_and_authorize_resource :class => 'Forem::Forum', :only => :show
    before_filter :authenticate_user!

    helper 'forem/topics'
    include ForumCommon

    def index
      @categories = Forem::Category.order('position DESC')
    end

    def show
      MixpanelDelay.new.track_app_event(
        'id' => current_user.id,
        'type' => 'View Coffee Shop',
        'properties' => {
      })
      tags_id = Forem::Tag.all.map { |element| element.id }
      tags_title = Forem::Tag.all.map { |element| element.tag }
      @tags_hash = Hash[tags_id.zip(tags_title.map {|i| i.include?(',') ? (i.split(/, /)) : i})]
      authorize! :show, @forum
      register_view

      if current_user
        mailbox = current_user.mailbox
        @key = params[:key]
        @container = params[:container]
        @sort = params[:sort]
        @search = params[:search] ? params[:search].downcase : params[:search]
        @is_public_search = false
        if @key == 'private'
          if @container == 'trash'
            @collection = mailbox.trash
          else
            if @sort == 'unread'
              @collection = mailbox.conversations.reorder(id: :asc).where("mailboxer_receipts.trashed = FALSE").where("mailboxer_receipts.is_read = FALSE")
            else
              if @container == 'trash'
                @collection = mailbox.trash
              else
                @collection = mailbox.conversations.where("mailboxer_receipts.trashed = FALSE")
              end
            end
          end
        else
          if @sort == 'search'
            if params[:tag].present?
              tag = Forem::Tag.find_by_tag(params[:tag])
              @collection = Forem::TopicTag.includes(:topic).where(tag_id: tag.id).map(&:topic)
            else
              matched_users_ids = User.where('user_name LIKE ?', "%#{@search}%").pluck(:id)

              array_of_tags_id = Forem::Tag.where('lower(tag) LIKE ?', "%#{@search}%").pluck(:id)
              @collection = []
              array_of_tags_id.each do |a|
                @collection += Forem::TopicTag.includes(:topic).where('tag_id IN (?)', array_of_tags_id).map(&:topic)
              end
              @collection += Forem::Topic.where('lower(subject) LIKE ? OR user_id IN (?)', "%#{@search}%", matched_users_ids)
              @collection = @collection.uniq
            end
            @is_public_search = true
          else
            @collection = Forem::Topic.all.by_most_recent_post
          end
        end
        # Kaminari allows to configure the method and param used
        #@topics = @topics.send(pagination_method, params[pagination_param]).per(Forem.per_page)

        respond_to do |format|
          format.html
          format.atom { render :layout => false }
        end
      else
        redirect_to main_app.new_user_session_path
      end
    end

    def sort
      redirect_to forem.forum_topics_path('coffee-shop', sort_by: params[:sort_by])
    end

    def sort_by
      @sort = params[:sort]
      if @sort == 'popular'
        #@collection = Forem::Topic.all.order(views_count: :desc)
        @collection = Forem::Topic.all
        @collection = @collection.sort_by {|obj| obj.views_table.inject(:+)}
        @collection.reverse!
      elsif @sort == 'following'
        @collection = Forem::Topic.where(id: Forem::Subscription.where(:subscriber_id => current_user).pluck(:topic_id))
      else
        @collection = Forem::Topic.all.by_most_recent_post
      end
    end

    private
    def register_view
      @forum.register_view_by(forem_user)
    end
  end
end