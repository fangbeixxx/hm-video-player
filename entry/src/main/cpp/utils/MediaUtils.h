#pragma once

#include <string>

/**
 * 媒体工具类
 */
class MediaUtils {
public:
    /**
     * 获取视频时长（秒）
     * @param path 文件路径
     * @return 时长（秒），失败返回 -1
     */
    static double getVideoDuration(const std::string& path);

    /**
     * 获取视频分辨率
     * @param path 文件路径
     * @param width 输出宽度
     * @param height 输出高度
     * @return 是否成功
     */
    static bool getVideoResolution(const std::string& path, int& width, int& height);

    /**
     * 截取视频缩略图
     * @param path 文件路径
     * @param timeSec 截取时间点（秒）
     * @param outPath 输出图片路径
     * @return 是否成功
     */
    static bool extractThumbnail(const std::string& path, double timeSec, const std::string& outPath);

    /**
     * 获取文件的编码信息
     */
    static std::string getCodecInfo(const std::string& path);
};
