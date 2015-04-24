module Forem
  class PostsController < Forem::ApplicationController
    before_filter :authenticate_forem_user
    before_filter :find_topic
    before_filter :reject_locked_topic!, :only => [:create]
    before_filter :block_spammers, :only => [:new, :create]
    before_filter :authorize_reply_for_topic!, :only => [:new, :create]
    before_filter :authorize_edit_post_for_forum!, :only => [:edit, :update]
    before_filter :find_post_for_topic, :only => [:show, :edit, :update, :destroy]
    before_filter :ensure_post_ownership!, :only => [:destroy]
    before_filter :authorize_destroy_post_for_forum!, :only => [:destroy]

    def show
      page = (@topic.posts.count.to_f / Forem.per_page.to_f).ceil
      redirect_to forum_topic_url(@topic.forum, @topic, pagination_param => page, anchor: "post-#{@post.id}")
    end

    def index

    end

    def new
      authorize_reply_for_topic!
      block_spammers
      @post = @topic.posts.build
      find_reply_to_post
      @id = params[:reply_to_id]
    end

    def create
      @post = @topic.posts.build(post_params)
      @post.user = forem_user
      @id = params[:post][:reply_to_id]
      respond_to do |format|
        if @post.save
          if params[:subscribe]
            @topic.subscribe_user(forem_user.id)
          end
          authorize_reply_for_topic!
          block_spammers
          @new_post = @topic.posts.build
          find_reply_to_post
          format.js
        else
          format.js {render 'create_empty'}
        end
      end
    end

    def edit
      @post = Forem::Post.find_by_id(params[:id])
      if !@post.nil?
        @topic = @post.topic
      end
    end

    def update
      respond_to do |format|
        if !@post.is_updateable?
          format.js { render js: 'alert(\'You cannot edit post after more than 5 minutes from last update.\');
                                   window.location.reload();'}
        else
          if @post.owner_or_admin?(forem_user) && @post.update_attributes(post_params)
            format.js
          end
        end
      end
    end

    def destroy
      @deleted_id = @post.id
      topic = @post.topic
      forum = @post.forum
      if @post.id == topic.posts.first.id
        @post.topic.destroy
        flash[:notice] = 'Topic has been deleted.'
        respond_to do |format|
          format.js { render js: "window.location = '#{main_app.forum_path('coffee-shop')}';" }
        end
      else
        @post.replies.each do |r|
          puts r.id
          r.destroy
        end
        @post.destroy
      end
    end

    def new_report
      @forum = params[:forum_id]
      @topic = params[:topic_id]
      @post = params[:post_id]
    end

    def create_report
      report = PostReports.new(user_id: current_user.id, post_id: params[:post_id], reason: params[:reason], post_type: 'public' )
      report.save
      redirect_to [@topic.forum, @topic], :notice => 'Post has been reported.'
    end

    private

    def post_params
      params.require(:post).permit(:text, :reply_to_id)
    end

    def authorize_reply_for_topic!
      authorize! :reply, @topic
    end

    def authorize_edit_post_for_forum!
      authorize! :edit_post, @topic.forum
    end

    def authorize_destroy_post_for_forum!
      authorize! :destroy_post, @topic.forum
    end

    def create_successful
      MixpanelDelay.new.track_app_event(
        'id' => current_user.id,
        'type' => 'Create Post',
        'properties' => {
      })
      Intercom::Event.delay.create(
        event_name: 'create-post',
        created_at: Time.now.to_i,
        user_id: current_user.i
      )
      flash[:notice] = t("forem.post.created")
      redirect_to forum_topic_path(@topic.forum, @topic, pagination_param => @topic.last_page, created: 't')
    end

    def create_failed
      respond_to do |format|
        #format.html {}
        format.js {}
      end
    end

    def destroy_successful
      if @post.topic.posts.count == 0
        @post.topic.destroy
        flash[:notice] = t("forem.post.deleted_with_topic")
        redirect_to [@topic.forum]
      else
        flash[:notice] = t("forem.post.deleted")
        redirect_to [@topic.forum, @topic]
      end
    end

    def update_successful
      redirect_to [@topic.forum, @topic], :notice => t('edited', :scope => 'forem.post')
    end

    def update_failed
      flash.now.alert = t("forem.post.not_edited")
      render :action => "edit"
    end

    def ensure_post_ownership!
      unless @post.owner_or_admin? forem_user
        flash[:alert] = t("forem.post.cannot_delete")
        redirect_to [@topic.forum, @topic] and return
      end
    end

    def find_topic
      @topic = Forem::Topic.friendly.find params[:topic_id]
    end

    def find_post_for_topic
      @post = @topic.posts.find params[:id]
    end

    def block_spammers
      if forem_user.forem_spammer?
        flash[:alert] = t('forem.general.flagged_for_spam') + ' ' +
            t('forem.general.cannot_create_post')
        redirect_to :back
      end
    end

    def reject_locked_topic!
      if @topic.locked?
        flash.alert = t("forem.post.not_created_topic_locked")
        redirect_to [@topic.forum, @topic] and return
      end
    end

    def find_reply_to_post
      @reply_to_post = @topic.posts.find_by_id(params[:reply_to_id])
    end
  end
end