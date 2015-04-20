require 'forum_common'
module Forem
  class TopicsController < Forem::ApplicationController
    helper 'forem/posts'
    before_filter :authenticate_forem_user
    before_filter :find_forum
    before_filter :block_spammers, :only => [:new, :create]
    include ForumCommon

    def show
      @created = true if params[:created].present?
      @sort = params[:sort]
      if find_topic
        register_view(@topic, forem_user)
        increment_views_table(@topic)
              MixpanelDelay.new.track_app_event(
        'id' => current_user.id,
        'type' => 'View Topic',
        'properties' => {
      })
        @posts = find_posts(@topic)
        # Kaminari allows to configure the method and param used
        @posts = @posts.send(pagination_method, params[pagination_param]).per(Forem.per_page)
      end
      @post = @topic.posts.build
      if params[:sort] == 'oldest'
        @posts = @posts.reorder('created_at' => :asc).where(reply_to_id: nil).where.not(id: @topic.posts.first.id)
      else
        @posts = @posts.reorder('created_at' => :desc).where(reply_to_id: nil).where.not(id: @topic.posts.first.id)
      end
      @new_id = DateTime.now.strftime('%Q')
    end

    def increment_views_table(topic)
      topic.views_table_will_change!
      view_table = topic.views_table
      view_table[6] += 1
      topic.update(views_table: view_table)
    end

    def refresh_posts
      @forum = find_forum
      @topic = forum_topics(@forum, forem_user).find(params[:topic_id])
      @all_posts = find_posts(@topic)
      @all_posts = @posts.where("id > ?", params[:after].to_i)
      @posts = @all_posts.where(reply_to_id: nil)
      @replies = @all_posts.where.not(reply_to_id: nil)
      if params[:sort] == 'newest'
        @posts = @posts.reorder('id desc')
      end
      @sort = params[:sort]
    end

    def new
      authorize! :create_topic, @forum
      @topic = @forum.topics.build
      @topic.posts.build
      # @tags = Forem::Tag.all # not used
      @new_id = DateTime.now.strftime('%Q')
    end

    def create
      authorize! :create_topic, @forum
      @topic = @forum.topics.build(topic_params)
      @topic.user = forem_user
      @topic.tags = Forem::Tag.where('id IN (?)', params[:topic][:tags].reject!(&:empty?))
      if @topic.save
        create_successful
      else
        create_unsuccessful
      end
    end

    def destroy
      @topic = @forum.topics.friendly.find(params[:id])
      if forem_user == @topic.user || forem_user.forem_admin?
        @topic.destroy
        destroy_successful
      else
        destroy_unsuccessful
      end
    end

    def subscribe
      if find_topic
        @topic.subscribe_user(forem_user.id)
        respond_to do |format|
          format.js
        end
      end
    end

    def unsubscribe
      respond_to do |format|
        if find_topic
          @topic.unsubscribe_user(forem_user.id)
          format.js { render 'subscribe' }
        end
      end
    end

    def index
      if params[:sort_by] == 'oldest'
        @my_topics = Forem::Topic.reorder(updated_at: :asc).where(id: Forem::Subscription.where(:subscriber_id => current_user).pluck(:topic_id))
      else params[:sort_by] == 'newest'
        @my_topics = Forem::Topic.reorder(updated_at: :desc).where(id: Forem::Subscription.where(:subscriber_id => current_user).pluck(:topic_id))
      end
    end

    # def search_panel
    #   tags_id = ForemTag.all.map { |element| element.id }
    #   tags_title = ForemTag.all.map { |element| element.tag }
    #   @tags_hash = Hash[tags_id.zip(tags_title.map {|i| i.include?(',') ? (i.split /, /) : i})]
    # end

    def search
      redirect_to main_app.forum_path('coffee-shop', sort: 'search', tag: params[:tag], search: params[:search])
    end

    protected

    def topic_params
      # params.require(:topic).permit(:subject, tags: [], :posts_attributes => [[:text]])
      params.require(:topic).permit(:subject, :posts_attributes => [[:text]])
    end

    def create_successful
      MixpanelDelay.new.track_app_event(
        'id' => current_user.id,
        'type' => 'Create Topic',
        'properties' => {
      })
      Intercom::Event.delay.create(
        event_name: 'create-topic',
        created_at: Time.now.to_i,
        user_id: current_user.id
      )
      redirect_to [@forum, @topic], :notice => t("forem.topic.created")
    end

    def create_unsuccessful
      flash.now.alert = t('forem.topic.not_created')
      render :action => 'new'
    end

    def destroy_successful
      flash[:notice] = t("forem.topic.deleted")

      redirect_to @topic.forum
    end

    def destroy_unsuccessful
      flash.alert = t("forem.topic.cannot_delete")

      redirect_to @topic.forum
    end

    def subscribe_successful
      flash[:notice] = t("forem.topic.subscribed")
      redirect_to :back
    end

    def unsubscribe_successful
      flash[:notice] = t("forem.topic.unsubscribed")
      redirect_to :back
    end

    private
    def find_forum
      @forum = Forem::Forum.friendly.find(params[:forum_id])
      authorize! :read, @forum
    end

    def find_posts(topic)
      posts = topic.posts
      unless forem_admin_or_moderator?(topic.forum)
        posts = posts.approved_or_pending_review_for(forem_user)
      end
      @posts = posts
    end

    def find_topic
      begin
        @topic = forum_topics(@forum, forem_user).friendly.find(params[:id])
        authorize! :read, @topic
      rescue ActiveRecord::RecordNotFound
        flash.alert = t("forem.topic.not_found")
        redirect_to @forum and return
      end
    end

    def register_view(topic, user)
      topic.register_view_by(user)
    end

    def block_spammers
      if forem_user.forem_spammer?
        flash[:alert] = t('forem.general.flagged_for_spam') + ' ' +
            t('forem.general.cannot_create_topic')
        redirect_to :back
      end
    end

    def forum_topics(forum, user)
      if forem_admin_or_moderator?(forum)
        forum.topics
      else
        forum.topics.visible.approved_or_pending_review_for(user)
      end
    end
  end
end