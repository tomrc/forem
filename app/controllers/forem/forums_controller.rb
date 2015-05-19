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
      authorize! :show, @forum
      register_view

      if can? :create_topic, @forum
        @topic = @forum.topics.build
        @topic.posts.build
        @new_id = DateTime.now.strftime('%Q')
      end

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
            @is_public_search = true
          else
            tags = Forem::Tag.where(hidden: true).pluck(:id)
            # @collection = Forem::Topic
            #               .joins('LEFT OUTER JOIN forem_topic_tags ON forem_topic_tags.topic_id = forem_topics.id')
            #               .where.not('forem_topic_tags.tag_id = ?', tag.id)
            #               .by_most_recent_post
            if tags.present?
              @collection = Forem::Topic
                            .where('forem_topics.id NOT IN (?)', Forem::TopicTag.select(:topic_id)
                              .where('forem_topic_tags.tag_id IN (?)', tags) )
                            .by_most_recent_post
            else
              @collection = Forem::Topic.by_most_recent_post
            end
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
        @collection = Forem::Topic.all.sort_by {|obj| obj.views_table.inject(:+)}.reverse!
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