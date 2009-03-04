class Cms::ContentController < Cms::ApplicationController

  before_filter :construct_path
  before_filter :redirect_non_cms_users_to_public_site
  before_filter :try_to_redirect
  before_filter :try_to_stream_file
  before_filter :check_access_to_page
  
  def show        
    render_page
    cache_page
  end

  private

  def construct_path
    @paths = params[:page_path] || params[:path] || []
    @path = "/#{@paths.join("/")}"
  end
  
  def redirect_non_cms_users_to_public_site
    @show_toolbar = false
    if Cms.caching_enabled?
      if cms_site?
        if current_user.able_to?(:edit_content, :publish_content)
          @show_toolbar = true
        else
          redirect_to url_without_cms_domain_prefix
        end
      end
    else
      if current_user.able_to?(:edit_content, :publish_content)
        @show_toolbar = true
      end
    end
  end
  
  def try_to_redirect
    if redirect = Redirect.find_by_from_path(@path)
      redirect_to redirect.to_path
    end    
  end

  def try_to_stream_file
    split = @paths.last.to_s.split('.')
    ext = split.size > 1 ? split.last.to_s.downcase : nil
    
    #Only try to stream cache file if it has an extension
    unless ext.blank?
      
      #Check access to file
      @attachment = Attachment.find_live_by_file_path(@path)
      if @attachment
        raise Cms::Errors::AccessDenied unless current_user.able_to_view?(@attachment)

        #Construct a path to where this file would be if it were cached
        @file = @attachment.full_file_location

        #Stream the file if it exists
        if @path != "/" && File.exists?(@file)
          send_file(@file, 
            :filename => @attachment.file_name,
            :type => @attachment.file_type,
            :disposition => "inline"
          ) 
        end    
      end
    end    
    
  end

  def check_access_to_page
    set_page_mode
    if current_user.able_to?(:edit_content, :publish_content)
      @page = Page.first(:conditions => {:path => @path})
      page_not_found unless @page
    else
      @page = Page.find_live_by_path(@path)
      page_not_found unless (@page && !@page.archived?)
    end

    unless current_user.able_to_view?(@page)
      store_location
      raise Cms::Errors::AccessDenied
    end

    # Doing this so if you are logged in, you never see the cached page
    # We are calling render_page just like the show action does
    # But since we do it from a before filter, the page doesn't get cached
    if logged_in?
      logger.info "Not Caching, user is logged in"
      render_page
    elsif !@page.cacheable?
      logger.info "Not Caching, page cachable is false"
      render_page
    elsif params[:cms_cache] == "false"
      logger.info "Not Caching, cms_cache is false"
      render_page
    end

  end
  
  def render_page
    prepare_params
    render :layout => @page.layout, :action => 'show'
  end
  
  #-- Other Methods --
  
  # This method gives the content type a chance to set some params
  # This is used to make SEO-friendly URLs possible
  def prepare_params
    if params[:prepare_with] && params[:prepare_with][:content_type] && params[:prepare_with][:method]
      content_type = params[:prepare_with][:content_type].constantize
      if content_type.respond_to?(params[:prepare_with][:method])
        # This call is expected to modify params
        logger.debug "Calling #{content_type.name}.#{params[:prepare_with][:method]} prepare method"
        content_type.send(params[:prepare_with][:method], params)
      else
        logger.debug "#{content_type.name} does not respond to #{params[:prepare_with][:method]}"
      end
    else
      logger.debug "No Prepare Method"
    end    
  end
    
  def page_not_found
    raise ActiveRecord::RecordNotFound.new("No page at '#{@path}'")
  end

  def set_page_mode
    @mode = @show_toolbar && current_user.able_to?(:edit_content) ? (params[:mode] || session[:page_mode] || "edit") : "view"
    session[:page_mode] = @mode      
  end

  
end